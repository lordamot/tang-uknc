// rt11sav.c - build an RT-11 floppy image around one .SAV file.
//
// The volume format is the one tools/rt11fs.py works on (the RT-11
// Volume and File Formats manual): block 1 is the home block and word
// 0724 of it names the first directory segment; a segment is two
// blocks, a five-word header (segments, next, highest, extra bytes per
// entry, first data block) and 14-byte entries - status, three RAD50
// words of name and type, length, job/channel, date - up to one with
// E.EOS.  Files lie one after another in entry order from the header's
// first data block, empty areas included, so an entry's block is the
// sum of the lengths before it.  Status bits are DEC's: E.MPTY 001000,
// E.PERM 002000, E.EOS 004000.
//
// The volume side works through two block callbacks so the same code
// runs on the host over a plain file (-DRT11SAV_HOST, make sav-test)
// and on the BL616 over FatFs.  A directory segment is handled whole in
// a 1 KB buffer; nothing here allocates a new segment or coalesces
// empties beyond what a fresh base disk needs.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "rt11sav.h"

#define BLK     512
#define E_MPTY  0x0200
#define E_PERM  0x0400
#define E_EOS   0x0800
#define ENTRY   14
#define SEGSZ   (2 * BLK)
#define HB_DIR  0x1d4          // 0724
#define DISKSZ  819200u

typedef struct {
  int (*read)(void *ctx, unsigned blk, void *buf);
  int (*write)(void *ctx, unsigned blk, const void *buf);
  void *ctx;
} rt11_io_t;

static const char RAD50[] = " ABCDEFGHIJKLMNOPQRSTUVWXYZ$.?0123456789";

static unsigned w16(const uint8_t *p) { return p[0] | (p[1] << 8); }
static void put16(uint8_t *p, unsigned v) { p[0] = v & 0xff; p[1] = (v >> 8) & 0xff; }

// three characters, space padded, to one RAD50 word
static unsigned r50(const char *s, int n) {
  unsigned v = 0;
  for(int i = 0; i < 3; i++) {
    char c = (i < n) ? s[i] : ' ';
    const char *p = strchr(RAD50, c);
    v = v * 40 + (p ? (unsigned)(p - RAD50) : 0);
  }
  return v;
}

// name (up to 6) and ext (up to 3) -> the entry's three words
static void r50name(const char *name, const char *ext, unsigned w[3]) {
  int n = strlen(name);
  w[0] = r50(name, n);
  w[1] = (n > 3) ? r50(name + 3, n - 3) : 0;
  w[2] = r50(ext, strlen(ext));
}

// A six-character RT-11 name from a FAT one: uppercase, RAD50 letters
// and digits only, the last extension dropped, "PROG" if nothing is left.
static void short_name(const char *fname, char *out) {
  const char *end = strrchr(fname, '.');
  if(!end || end == fname) end = fname + strlen(fname);
  int n = 0;
  for(const char *p = fname; p < end && n < 6; p++) {
    char c = toupper((unsigned char)*p);
    if((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '$') out[n++] = c;
  }
  out[n] = 0;
  if(!n) strcpy(out, "PROG");
}

unsigned rt11sav_date(int year, int month, int day) {
  int y = year - 1972;
  if(y < 0 || month < 1 || month > 12 || day < 1 || day > 31) return 0;
  return ((y >> 5) & 3) << 14 | (month << 10) | (day << 5) | (y & 31);
}

// ---------------------------------------------------------------------
// the directory
// ---------------------------------------------------------------------
static int dir_start(const rt11_io_t *io, unsigned *start) {
  uint8_t b[BLK];
  if(io->read(io->ctx, 1, b)) return -1;
  unsigned d = w16(b + HB_DIR);
  *start = (d >= 2 && d < 64) ? d : 6;
  return 0;
}

static int seg_rw(const rt11_io_t *io, unsigned start, unsigned seg, uint8_t *buf, int write) {
  unsigned blk = start + 2 * (seg - 1);
  for(int i = 0; i < 2; i++) {
    int r = write ? io->write(io->ctx, blk + i, buf + i * BLK)
                  : io->read(io->ctx, blk + i, buf + i * BLK);
    if(r) return -1;
  }
  return 0;
}

// Walk the segments.  For each entry the callback sees the segment
// buffer, the entry offset, its data block and the entry size; it
// returns 0 to go on, 1 to stop (the segment is written back if
// 'dirty' was set), -1 on error.
typedef int (*entry_fn)(uint8_t *seg, unsigned off, unsigned blk, unsigned esize, void *arg, int *dirty);

static int dir_walk(const rt11_io_t *io, entry_fn fn, void *arg) {
  static uint8_t seg[SEGSZ];
  unsigned start;
  if(dir_start(io, &start)) return -1;
  unsigned s = 1;
  while(s) {
    if(seg_rw(io, start, s, seg, 0)) return -1;
    unsigned next = w16(seg + 2), extra = w16(seg + 6), blk = w16(seg + 8);
    unsigned esize = ENTRY + extra;
    int dirty = 0;
    for(unsigned off = 10; off + esize <= SEGSZ; off += esize) {
      unsigned status = w16(seg + off);
      if(status & E_EOS) break;
      int r = fn(seg, off, blk, esize, arg, &dirty);
      if(r < 0) return -1;
      if(r > 0) {
        if(dirty && seg_rw(io, start, s, seg, 1)) return -1;
        return 1;
      }
      blk += w16(seg + off + 8);
    }
    if(dirty && seg_rw(io, start, s, seg, 1)) return -1;
    s = next;
  }
  return 0;
}

typedef struct { unsigned name[3]; unsigned blk, len; } find_t;

static int find_cb(uint8_t *seg, unsigned off, unsigned blk, unsigned esize, void *arg, int *dirty) {
  find_t *f = arg;
  (void)esize; (void)dirty;
  if((w16(seg + off) & E_PERM) && w16(seg + off + 2) == f->name[0] &&
     w16(seg + off + 4) == f->name[1] && w16(seg + off + 6) == f->name[2]) {
    f->blk = blk; f->len = w16(seg + off + 8);
    return 1;
  }
  return 0;
}

// 1 if name.ext is on the volume (block and length filled in), 0 if not, -1 on error
static int rt11_find(const rt11_io_t *io, const char *name, const char *ext, unsigned *blk, unsigned *len) {
  find_t f;
  r50name(name, ext, f.name);
  int r = dir_walk(io, find_cb, &f);
  if(r == 1) { *blk = f.blk; *len = f.len; }
  return r;
}

static int rm_cb(uint8_t *seg, unsigned off, unsigned blk, unsigned esize, void *arg, int *dirty) {
  find_t *f = arg;
  (void)blk; (void)esize;
  if((w16(seg + off) & E_PERM) && w16(seg + off + 2) == f->name[0] &&
     w16(seg + off + 4) == f->name[1] && w16(seg + off + 6) == f->name[2]) {
    put16(seg + off, E_MPTY);
    *dirty = 1;
    return 1;
  }
  return 0;
}

typedef struct { unsigned name[3]; unsigned need, date, blk; int full; } alloc_t;

static int alloc_cb(uint8_t *seg, unsigned off, unsigned blk, unsigned esize, void *arg, int *dirty) {
  alloc_t *a = arg;
  if(!(w16(seg + off) & E_MPTY) || w16(seg + off + 8) < a->need) return 0;
  unsigned rest = w16(seg + off + 8) - a->need;
  if(rest) {
    // split: shift this and everything after it, the EOS included, up one entry
    unsigned eos = off;
    while(eos + esize <= SEGSZ && !(w16(seg + eos) & E_EOS)) eos += esize;
    if(eos + 2 * esize > SEGSZ) { a->full = 1; return 1; }
    memmove(seg + off + esize, seg + off, eos + esize - off);
    put16(seg + off + esize + 8, rest);
  }
  memset(seg + off, 0, esize);
  put16(seg + off, E_PERM);
  put16(seg + off + 2, a->name[0]);
  put16(seg + off + 4, a->name[1]);
  put16(seg + off + 6, a->name[2]);
  put16(seg + off + 8, a->need);
  put16(seg + off + 12, a->date);
  a->blk = blk;
  *dirty = 1;
  return 1;
}

// Make room for name.ext of nblocks: an entry of that name is freed
// first, then the first empty area big enough is split.  Returns the
// data block, or -1 (no room: err says whether the directory or the
// disk is full).
static int rt11_alloc(const rt11_io_t *io, const char *name, const char *ext, unsigned nblocks,
                      unsigned date, unsigned *blk, const char **err) {
  alloc_t a = { .need = nblocks, .date = date, .full = 0 };
  r50name(name, ext, a.name);
  find_t f; memcpy(f.name, a.name, sizeof(f.name));
  if(dir_walk(io, rm_cb, &f) < 0) { *err = "dir read"; return -1; }
  int r = dir_walk(io, alloc_cb, &a);
  if(r < 0) { *err = "dir write"; return -1; }
  if(r == 0) { *err = "disk full"; return -1; }
  if(a.full) { *err = "dir full"; return -1; }
  *blk = a.blk;
  return 0;
}

// ---------------------------------------------------------------------
// the two files.  A "source" hands out the next 512 bytes, zero padded.
// ---------------------------------------------------------------------
typedef int (*src_fn)(void *arg, uint8_t *buf);

static int rt11_put(const rt11_io_t *io, const char *name, const char *ext, unsigned size,
                    unsigned date, src_fn src, void *arg, const char **err) {
  unsigned nblocks = (size + BLK - 1) / BLK, blk;
  if(!nblocks) { *err = "empty file"; return -1; }
  if(rt11_alloc(io, name, ext, nblocks, date, &blk, err)) return -1;
  uint8_t buf[BLK];
  for(unsigned i = 0; i < nblocks; i++) {
    memset(buf, 0, BLK);
    if(src(arg, buf)) { *err = "read SAV"; return -1; }
    if(io->write(io->ctx, blk + i, buf)) { *err = "write DSK"; return -1; }
  }
  return 0;
}

// STARTS.COM: whatever the base has, then "R name".  RT-11 pads a text
// file with NULs to the block end; the text is what comes before the
// first of them.
typedef struct { const char *text; unsigned pos, len; } text_src_t;
static int text_src(void *arg, uint8_t *buf) {
  text_src_t *t = arg;
  unsigned n = t->len - t->pos;
  if(n > BLK) n = BLK;
  memcpy(buf, t->text + t->pos, n);
  t->pos += n;
  return 0;
}

static int rt11_starts(const rt11_io_t *io, const char *prog, unsigned date, const char **err) {
  static char text[2 * BLK + 16];
  unsigned blk, len, n = 0;
  int r = rt11_find(io, "STARTS", "COM", &blk, &len);
  if(r < 0) { *err = "dir read"; return -1; }
  if(r == 1) {
    uint8_t buf[BLK];
    for(unsigned i = 0; i < len && i < 2; i++) {     // two blocks of text is plenty
      if(io->read(io->ctx, blk + i, buf)) { *err = "read DSK"; return -1; }
      for(unsigned j = 0; j < BLK && buf[j]; j++) text[n++] = buf[j];
      if(memchr(buf, 0, BLK)) break;
    }
    while(n && (text[n-1] == '\r' || text[n-1] == '\n' || text[n-1] == ' ')) n--;
    if(n) { text[n++] = '\r'; text[n++] = '\n'; }
  }
  n += sprintf(text + n, "R %s\r\n", prog);
  text_src_t t = { text, 0, n };
  return rt11_put(io, "STARTS", "COM", n, date, text_src, &t, err);
}

// The name the SAV gets: the shortened FAT name, and if the base disk
// already has a file of that name (DIR.SAV, say), five letters and a
// digit instead - never over one of the system's own programs.
static int rt11_pick_name(const rt11_io_t *io, const char *fname, char *name, const char **err) {
  unsigned blk, len;
  short_name(fname, name);
  int r = rt11_find(io, name, "SAV", &blk, &len);
  if(r < 0) { *err = "dir read"; return -1; }
  if(r == 0) return 0;
  if(strlen(name) > 5) name[5] = 0;
  int n = strlen(name);
  for(char d = '1'; d <= '9'; d++) {
    name[n] = d; name[n+1] = 0;
    r = rt11_find(io, name, "SAV", &blk, &len);
    if(r < 0) { *err = "dir read"; return -1; }
    if(r == 0) return 0;
  }
  *err = "name taken";
  return -1;
}

// Everything on the volume: name the SAV, add it, rewrite STARTS.COM.
// 'prog' comes back with the RT-11 name used.
static int rt11_build(const rt11_io_t *io, const char *fname, unsigned size, unsigned date,
                      src_fn src, void *arg, char *prog, const char **err) {
  if(rt11_pick_name(io, fname, prog, err)) return -1;
  if(rt11_put(io, prog, "SAV", size, date, src, arg, err)) return -1;
  if(rt11_starts(io, prog, date, err)) return -1;
  return 0;
}

// ---------------------------------------------------------------------
// The host build: plain files, for make sav-test
// ---------------------------------------------------------------------
#ifdef RT11SAV_HOST

static int host_read(void *ctx, unsigned blk, void *buf) {
  FILE *f = ctx;
  return fseek(f, (long)blk * BLK, SEEK_SET) || fread(buf, 1, BLK, f) != BLK;
}
static int host_write(void *ctx, unsigned blk, const void *buf) {
  FILE *f = ctx;
  return fseek(f, (long)blk * BLK, SEEK_SET) || fwrite(buf, 1, BLK, f) != BLK;
}
static int host_src(void *arg, uint8_t *buf) {
  FILE *f = arg;
  size_t n = fread(buf, 1, BLK, f);
  return n == 0 && ferror(f);
}

int main(int argc, char **argv) {
  if(argc < 4) {
    fprintf(stderr, "usage: %s BASE.DSK PROGRAM.SAV OUT.DSK [fat-name]\n", argv[0]);
    return 2;
  }
  const char *fatname = argc > 4 ? argv[4] : strrchr(argv[2], '/') ? strrchr(argv[2], '/') + 1 : argv[2];
  FILE *base = fopen(argv[1], "rb"), *sav = fopen(argv[2], "rb"), *out = fopen(argv[3], "w+b");
  if(!base || !sav || !out) { perror("open"); return 1; }
  static uint8_t buf[4096];
  size_t n, total = 0;
  while((n = fread(buf, 1, sizeof(buf), base)) > 0) { fwrite(buf, 1, n, out); total += n; }
  if(total != DISKSZ) { fprintf(stderr, "bad RT11 base: %zu bytes\n", total); return 1; }
  fseek(sav, 0, SEEK_END);
  unsigned size = ftell(sav);
  fseek(sav, 0, SEEK_SET);
  rt11_io_t io = { host_read, host_write, out };
  char prog[8];
  const char *err = "";
  if(rt11_build(&io, fatname, size, rt11sav_date(2026, 9, 3), host_src, sav, prog, &err)) {
    fprintf(stderr, "err: %s\n", err);
    return 1;
  }
  fclose(out);
  printf("%s: %s as %s.SAV, STARTS.COM runs it\n", argv[3], fatname, prog);
  return 0;
}

#else
// ---------------------------------------------------------------------
// The firmware build: FatFs on the card
// ---------------------------------------------------------------------
#include <ff.h>
#include "sdc.h"

static int fat_read(void *ctx, unsigned blk, void *buf) {
  UINT n;
  return f_lseek(ctx, (FSIZE_t)blk * BLK) != FR_OK || f_read(ctx, buf, BLK, &n) != FR_OK || n != BLK;
}
static int fat_write(void *ctx, unsigned blk, const void *buf) {
  UINT n;
  return f_lseek(ctx, (FSIZE_t)blk * BLK) != FR_OK || f_write(ctx, buf, BLK, &n) != FR_OK || n != BLK;
}
static int fat_src(void *arg, uint8_t *buf) {
  UINT n;
  return f_read(arg, buf, BLK, &n) != FR_OK;
}

int rt11sav_make(const char *dir, const char *name, unsigned date, char *err, int errlen) {
  // three FILs are a sector buffer each; the OSD task's stack is 8 KB
  static FIL base, sav, out;
  int have_base = 0, have_sav = 0, have_out = 0, ret = -1;
  const char *reason = "failed";
  uint8_t *buf = malloc(4096);
  if(!buf) { reason = "no memory"; goto done; }

  sdc_lock();

  if(f_open(&base, RT11SAV_DIR "/" RT11SAV_BASE, FA_OPEN_EXISTING | FA_READ) != FR_OK &&
     f_open(&base, RT11SAV_DIR "/" RT11SAV_BASE2, FA_OPEN_EXISTING | FA_READ) != FR_OK) {
    reason = "no RT11 base"; goto out;
  }
  have_base = 1;
  if(f_size(&base) != DISKSZ) { reason = "bad RT11 base"; goto out; }

  {
    char path[strlen(dir) + strlen(name) + 2];
    strcpy(path, dir); strcat(path, "/"); strcat(path, name);
    if(f_open(&sav, path, FA_OPEN_EXISTING | FA_READ) != FR_OK) { reason = "no SAV file"; goto out; }
  }
  have_sav = 1;
  if(f_size(&sav) == 0) { reason = "empty SAV"; goto out; }

  if(f_open(&out, RT11SAV_DIR "/" RT11SAV_DISK, FA_CREATE_ALWAYS | FA_WRITE | FA_READ) != FR_OK) {
    reason = "cannot write"; goto out;
  }
  have_out = 1;

  // the copy, 4 KB at a time
  for(unsigned pos = 0; pos < DISKSZ; pos += 4096) {
    UINT rd = 0, wr = 0;
    if(f_read(&base, buf, 4096, &rd) != FR_OK || rd != 4096 ||
       f_write(&out, buf, 4096, &wr) != FR_OK || wr != 4096) { reason = "copy failed"; goto out; }
  }

  {
    rt11_io_t io = { fat_read, fat_write, &out };
    char prog[8];
    if(rt11_build(&io, name, f_size(&sav), date, fat_src, &sav, prog, &reason)) goto out;
    printf("RT11SAV.DSK: %s as %s.SAV\r\n", name, prog);
  }
  if(f_sync(&out) != FR_OK) { reason = "write DSK"; goto out; }
  ret = 0;

out:
  if(have_out) f_close(&out);
  if(have_sav) f_close(&sav);
  if(have_base) f_close(&base);
  sdc_unlock();
done:
  free(buf);
  if(ret) { strncpy(err, reason, errlen - 1); err[errlen - 1] = 0; printf("RT11SAV.DSK: %s\r\n", reason); }
  return ret;
}
#endif
