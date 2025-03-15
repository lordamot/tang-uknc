/*
  sysctrl.h

  MiSTeryNano system control interface
*/

#ifndef SYS_CTRL_H
#define SYS_CTRL_H

#include "spi.h"

// the MCU can adopt to the core running to e.g.
// change the menu and the keyboard mapping
#define CORE_ID_UNKNOWN  0x00
#define CORE_ID_ATARI_ST 0x01
#define CORE_ID_C64      0x02
#define CORE_ID_UNEON    0x03
#define CORE_ID_AMIGA    0x04
#define CORE_ID_UKNC     0x05
#define CORE_ID_AGAT9    0x06
#define CORE_ID_VIC20    0x10

extern unsigned char core_id;

int  sys_status_is_valid(spi_t *);
void sys_set_leds(spi_t *, char);
void sys_set_rgb(spi_t *, unsigned long);
unsigned char sys_get_buttons(spi_t *);
void sys_set_val(spi_t *, char, uint8_t);
unsigned char sys_irq_ctrl(spi_t *, unsigned char);
void sys_handle_interrupts(unsigned char);

#endif // SYS_CTRL_H
