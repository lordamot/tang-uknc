#ifndef SDC_H
#define SDC_H

#include "spi.h"

// up to four image files can be open. E.g. two
// floppy disks and two ACSI hard drives
#define MAX_DRIVES  5

// One more slot that is browsed but never mounted: the OSD's "Run SAV:"
// entry (menu.c) walks the card for .SAV files through it, so it has a
// working directory and a remembered name like a drive, but no open
// image, no core-side drive and no line in the settings file.
#define SDC_SLOT_SAV  MAX_DRIVES

// fatfs mounts the card under /sd
#define CARD_MOUNTPOINT "/sd"

typedef struct {
  char *name;
  unsigned long len;
  int is_dir;
} sdc_dir_entry_t;

typedef struct {
  int len;
  sdc_dir_entry_t *files;
} sdc_dir_t;

int sdc_init(spi_t *spi);
int sdc_image_open(int drive, char *name);
sdc_dir_t *sdc_readdir(int drive, char *name, const char *exts);
int sdc_handle_event(void);
int sdc_is_ready(void);
void sdc_lock(void);
void sdc_unlock(void);
char *sdc_get_image_name(int drive);
char *sdc_get_cwd(int drive);
void sdc_set_default(int drive, const char *name);
void sdc_set_image_name(int drive, const char *name);

#endif // SDC_H
