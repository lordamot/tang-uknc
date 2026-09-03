// rt11sav.h - "Run SAV": an RT-11 floppy image made on the fly around
// one .SAV file, for the OSD's "Run SAV:" entry (menu.c).
//
// rt11sav_make() copies RT11BASE.DSK from the card's root to
// RT11SAV.DSK beside it, adds the .SAV at dir/name under a six-letter
// RT-11 name, and rewrites STARTS.COM so the monitor runs it at boot.
// The caller mounts the result.  Returns 0, or -1 with a short reason
// in err (fits an OSD line after "err: ").  date is the RT-11 date word
// for the new directory entries, 0 for none.
#ifndef RT11SAV_H
#define RT11SAV_H

#define RT11SAV_DIR   "/sd"
#define RT11SAV_BASE  "RT11BASE.DSK"
#define RT11SAV_BASE2 "BASERT11.DSK"   // the name soft/ ships it under
#define RT11SAV_DISK  "RT11SAV.DSK"

int rt11sav_make(const char *dir, const char *name, unsigned date,
                 char *err, int errlen);

// RT-11's date word: year 1972.., month 1..12, day 1..31
unsigned rt11sav_date(int year, int month, int day);

#endif // RT11SAV_H
