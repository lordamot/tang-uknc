/*
  sdl_menu_test.c

  SDL (native PC) version of the MiSTeryNano menu for testing purposes
 */

// mount image locally to modify it
// sudo mount -o offset=1048576 sd.img /mnt

#include <SDL.h>
#include "u8g2.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "ff.h"
#include "diskio.h"
#include "sysctrl.h"

#include "menu.h"

u8g2_t u8g2;

unsigned char core_id = CORE_ID_ATARI_ST;  // see sysctrl.h
// unsigned char core_id = CORE_ID_C64;

static FATFS fs;
static FIL fil;

// simple sd image read by fatfs
static int sdc_status() { return 0; }
static int sdc_initialize() { return 0; }

static FILE *img = NULL;

static void check_img(void) {
  if(!img) {
    img = fopen("sd.img", "r+b");
    if(!img) {
      perror("sd.img not loaded:");
      exit(-1);
    }
  }
}

static int sdc_write(const BYTE *buff, LBA_t sector, UINT count) {
  check_img();
  
  printf("sdc_write(%d, %p, %d)\n", sector, buff, count);
  fseek(img, 512*sector, SEEK_SET);
  fwrite(buff, 512, count, img);
  
  return 0;
}

static int sdc_read(BYTE *buff, LBA_t sector, UINT count) {
  check_img();
  
  printf("sdc_read(%d, %p, %d)\n", sector, buff, count);
  fseek(img, 512*sector, SEEK_SET);
  fread(buff, 512, count, img);
  
  return 0;
}

void vTaskDelay(int ms) { }

void sdc_lock(void) {}
void sdc_unlock(void) {}
int sdc_is_ready(void) { return 1; }

static int sdc_ioctl(BYTE cmd, void *buff) {
  printf("sdc_ioctl(%d, %p)\n", cmd, buff);
  return 0;
}
 
static DSTATUS Translate_Result_Code(int result) { return result; }

static int fs_init() {
  FRESULT res_msc;

  FATFS_DiskioDriverTypeDef MSC_DiskioDriver = { NULL };
  MSC_DiskioDriver.disk_status = sdc_status;
  MSC_DiskioDriver.disk_initialize = sdc_initialize;
  MSC_DiskioDriver.disk_write = sdc_write;
  MSC_DiskioDriver.disk_read = sdc_read;
  MSC_DiskioDriver.disk_ioctl = sdc_ioctl;
  MSC_DiskioDriver.error_code_parsing = Translate_Result_Code;
  
  disk_driver_callback_init(DEV_SD, &MSC_DiskioDriver);
  
  res_msc = f_mount(&fs, "/sd", 1);
  if (res_msc != FR_OK) {
    printf("mount fail,res:%d\r\n", res_msc);
    return -1;
  }
  return 0;
}

#include "sdc.h"

static char *cwd[MAX_DRIVES] = { NULL, NULL, NULL, NULL };
static char *image_name[MAX_DRIVES] = { NULL, NULL, NULL, NULL };

char *sdc_get_image_name(int drive) {
  return image_name[drive];
}

char *sdc_get_cwd(int drive) {
  return cwd[drive];
}

void sdc_set_default(int drive, const char *name) {
  // a valid filename will currently always begin with /sd
  if(strncasecmp(name, CARD_MOUNTPOINT, strlen(CARD_MOUNTPOINT)) == 0) {
    // name should consist of path and image name
    char *p = strrchr(name+strlen(CARD_MOUNTPOINT), '/');
    if(p && *p) {
      if(cwd[drive]) free(cwd[drive]);
      cwd[drive] = strndup(name, p-name);
      if(image_name[drive]) free(image_name[drive]);
      image_name[drive] = strdup(p+1);
    }
  }
}

int sdc_image_open(int drive, char *name) {
  // forget about any previous name
  if(image_name[drive]) {
    free(image_name[drive]);
    image_name[drive] = NULL;
  }

  if(!name) return 0;
  
  char fname[strlen(cwd[drive]) + strlen(name) + 2];
  strcpy(fname, cwd[drive]);
  strcat(fname, "/");
  strcat(fname, name);

  printf("opening image %s\n", fname);
  
  if(f_open(&fil, fname, FA_OPEN_EXISTING | FA_READ) != 0) {
    printf("file open failed\n");
    return -1;
  }
 
  printf("file opened, cl=%d\n", fil.obj.sclust);

  // remember current image name
  image_name[drive] = strdup(name);

  return 0;
}

sdc_dir_t *sdc_readdir(int drive, char *name, const char *exts) {
  static sdc_dir_t sdc_dir = { 0, NULL };

  // set default path
  if(!cwd[drive]) cwd[drive] = strdup(CARD_MOUNTPOINT);

  int dir_compare(const void *p1, const void *p2) {
    sdc_dir_entry_t *d1 = (sdc_dir_entry_t *)p1;
    sdc_dir_entry_t *d2 = (sdc_dir_entry_t *)p2;

    // comparing directory with regular file?
    if(d1->is_dir != d2->is_dir)
      return d2->is_dir - d1->is_dir;

    return strcasecmp(d1->name, d2->name);    
  }

  void append(sdc_dir_t *dir, FILINFO *fno) {
    if(!(dir->len%8))
      // allocate room for 8 more entries
      dir->files = reallocarray(dir->files, dir->len + 8, sizeof(sdc_dir_entry_t));
      
    dir->files[dir->len].name = strdup(fno->fname);
    dir->files[dir->len].is_dir = (fno->fattrib & AM_DIR)?1:0;
    dir->len++;
  }

  // check if a file name matches any of the extensions given
  char ext_match(char *name, const char *exts) {
    // check if name has an extension at all
    char *dot = strrchr(name, '.');
    if(!dot) return 0;

    // iterate over all extensions
    const char *ext = exts;
    while(1) {
      const char *p = ext;
      while(*p && *p != '+' && *p != ';') p++;  // search of end of ext
      int len = p-ext;

      // check if length would match
      if(strlen(dot+1) == len)
	if(!strncasecmp(dot+1, ext, len))
	  return 1;  // it's a match
      
      // end of extension string reached: nothing found
      if(!*p) return 0;
      
      ext = p+1;
    }
    return 0;
  }
  
  DIR dir;
  FILINFO fno;

  // assemble name before we free it
  if(name) {
    if(strcmp(name, "..")) {
      // alloc a longer string to fit new cwd
      char *n = malloc(strlen(cwd[drive])+strlen(name)+2);  // both strings + '/' and '\0'
      strcpy(n, cwd[drive]); strcat(n, "/"); strcat(n, name);
      free(cwd[drive]);
      cwd[drive] = n;
    } else {
      // no real need to free here, the unused parts will be free'd
      // once the cwd length increases. The menu relies on this!!!
      strrchr(cwd[drive], '/')[0] = 0;
    }
  }
  
  // free existing file names
  if(sdc_dir.files) {
    for(int i=0;i<sdc_dir.len;i++)
      free(sdc_dir.files[i].name);

    free(sdc_dir.files);
    sdc_dir.len = 0;
    sdc_dir.files = NULL;
  }

  // add "<UP>" entry for anything but root
  if(strcmp(cwd[drive], "/sd") != 0) {
    strcpy(fno.fname, "..");
    fno.fattrib = AM_DIR;
    append(&sdc_dir, &fno);
  } else {
    // the root also gets a special entry for "eject"
    strcpy(fno.fname, "/No Disk");
    fno.fattrib = AM_DIR;
    append(&sdc_dir, &fno);    
  }

  printf("max name len = %d\n", FF_LFN_BUF);

  int ret = f_opendir(&dir, cwd[drive]);

  printf("opendir(%d, %s)=%d\n", drive, cwd[drive], ret);
  
  do {
    f_readdir(&dir, &fno);
    if(fno.fname[0] != 0 && !(fno.fattrib & (AM_HID|AM_SYS)) ) {
      printf("%s %s, len=%ld\n", (fno.fattrib & AM_DIR) ? "dir: ":"file:", fno.fname, fno.fsize);
      // only accept directories or matching files
      if((fno.fattrib & AM_DIR) || ext_match(fno.fname, exts))
	append(&sdc_dir, &fno);
    }
  } while(fno.fname[0] != 0);

  f_closedir(&dir);

  qsort(sdc_dir.files, sdc_dir.len, sizeof(sdc_dir_entry_t), dir_compare);

  return &sdc_dir;
}

void osd_enable(osd_t *, char) { }

void sys_set_val(spi_t *, const char id, uint8_t v) {
  printf("SYS SET %c=%d\n", id, v);
}

static LBA_t clst2sect(DWORD clst) {
  clst -= 2;
  if (clst >= fs.n_fatent - 2)   return 0;
  return fs.database + (LBA_t)fs.csize * clst;
}

int main(void) {
  u8g2_SetupBuffer_SDL_128x64(&u8g2, &u8g2_cb_r0);
  u8x8_InitDisplay(u8g2_GetU8x8(&u8g2));

  fs_init();

  menu_t *menu = menu_init(&u8g2);
  menu_do(menu, 0);

  int k = -1;

  do {
    k = u8g_sdl_get_key();
    int event = -1;
    if(k >= 0) {
      // printf("K = %d\n", k);
      if ( k == 276 ) event = MENU_EVENT_LEFT;
      if ( k == 275 ) event = MENU_EVENT_RIGHT;
      if ( k == 274 ) event = MENU_EVENT_DOWN;
      if ( k == 273 ) event = MENU_EVENT_UP;
      if ( k == ' ' ) event = MENU_EVENT_SELECT;
      if ( k == 'o' ) event = MENU_EVENT_PGUP;
      if ( k == 'p' ) event = MENU_EVENT_PGDOWN;
    }    
    menu_do(menu, event);
    if(event == -1) SDL_Delay(40);
  } while(k != 'q');
  
  return 0;
}

