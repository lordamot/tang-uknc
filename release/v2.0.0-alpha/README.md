# UKNC Nano 2.0.0 alpha

| file | size | what it is |
|---|---|---|
| `tang.fs` | 7 262 008 | the FPGA bitstream for the Tang Nano 20K |
| `bl616.bin` | 442 016 | the MCU firmware for the BL616 board |

`tang.fs` - прошивка ПЛИС, `bl616.bin` - прошивка МК.  Как соединить платы, прошить и пользоваться - ниже, по-русски и по-английски; подробности в `howto-ru.md` / `howto.md` репозитория.

---

# UKNC Nano

**МС0511 (УКНЦ)** - советская двухпроцессорная PDP-11-совместимая машина
1987 года - на **Tang Nano 20K** с платой **BL616** (M0S Dock) рядом.
Аппаратная часть - **Алексей Гуров**; линия 2.x - Сергей Лемешев и Claude
Code.  Версия - в файле `VERSION`, история - в `CHANGELOG.md`, лицензия -
MIT (`LICENCE.md`).  *English below.*

Готовые прошивки - в [Releases](https://github.com/lordamot/tang-uknc/releases)
и в `bin/`: `tang.fs` для ПЛИС, `bl616.bin` для МК.

## Что умеет

- Оба процессора К1801ВМ2, экран по HDMI, звук по HDMI и по I²S.
- Четыре дисковода из файлов `.dsk` на SD-карте, у каждого своя защита от записи.
- Жёсткий диск: IDE-картридж с ПЗУ WD из файла `.img`, CHS и LBA28.
- Звуковой модуль Aberrant - три AY-3-8912 - и два Covox: `177372` и порт принтера `177100`.
- Мышь (USB-мышь на BL616) и часы реального времени картриджа Kakave+.
- Клавиатура USB, переведённая в матрицу УКНЦ.
- Меню по **F12**: образы, «Run SAV:» (любой `.SAV` становится загрузочной
  дискетой RT-11), и страница «Hardware», где каждое устройство можно
  убрать из машины - выключенное не отвечает на шине, как на настоящей
  УКНЦ без этой платы.

## Что нужно

- Tang Nano 20K, плата BL616 (M0S Dock), SD-карта FAT32, USB-клавиатура.
- Семь проводов между платами - распиновка **как в исходном MiSTeryNano**
  (до августа 2026 года была другая; старую плату нужно переразвести):

```
Tang Nano 20K   BL616
42              io10   MISO
41              io11   MOSI
56              io12   CSN
54              io13   SCK
51              io14   IRQ
GND             GND
+5              +5
```

Звук I²S - на выводах 71 (BCK), 72 (WS), 73 (DIN), 74 (разрешение
усилителя); по HDMI звук идёт сам.  Последовательный порт машины -
выводы 69/70, то есть USB-C разъём Tang.

## Как прошить

**BL616** - через его загрузчик: удерживая **BOOT**, подключить USB (или
нажать **RST**), отпустить BOOT; плата появится как последовательный
порт.  Дальше либо BLDevCube (чип BL616/BL618, вкладка MCU, файл
`bin/bl616.bin`, адрес `0x00000000`, скорость 2000000, Create & Download),
либо из этого репозитория:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

После прошивки нажать RST.

**Tang Nano 20K** - через openFPGALoader (или Gowin Programmer):

```sh
openFPGALoader -b tangnano20k -f bin/tang.fs     # во флеш
make flash-fpga-flash                            # то же из репозитория
```

и **выключить-включить питание**: после записи во флеш плата продолжает
работать со старой прошивкой, пока её не перезапустить.

## Как пользоваться

Карта - в слот Tang Nano 20K: образы `.dsk` (819 200 байт) и `.img` в
любых папках.  **F12** открывает меню; курсор - по пунктам, влево/вправо -
значение, пробел или Enter - выбрать, ESC - закрыть.  Первый диск - `FDD0:`
на главном экране, затем `Reset`; остальное - в `Hardware`.  «Save
settings» пишет `/uknc.ini` на карту.  Подробно - `howto-ru.md`.

---

# UKNC Nano

The **МС0511 (УКНЦ)**, a two-processor PDP-11-compatible Soviet machine of
1987, on a **Tang Nano 20K** with a **BL616** board (M0S Dock) beside it.
Hardware by **Alexey Gurov**; the 2.x line by Sergei Lemeshev and Claude
Code.  The version is in `VERSION`, the history in `CHANGELOG.md`, the
licence is MIT (`LICENCE.md`).

Ready-made binaries are in [Releases](https://github.com/lordamot/tang-uknc/releases)
and in `bin/`: `tang.fs` for the FPGA, `bl616.bin` for the MCU.

## Features

- Both К1801ВМ2 processors, the display over HDMI, sound over HDMI and I²S.
- Four floppies from `.dsk` files on the SD card, each with its own write protection.
- A hard disk: the IDE cartridge with its WD ROM from an `.img` file, CHS and LBA28.
- The Aberrant sound module - three AY-3-8912s - and two Covox DACs: `177372` and printer port `177100`.
- The Kakave+ cartridge's mouse (a USB mouse on the BL616) and real-time clock.
- A USB keyboard translated into the УКНЦ matrix.
- A menu on **F12**: images, "Run SAV:" (any `.SAV` becomes a bootable
  RT-11 floppy), and a "Hardware" page where every device can be taken
  out of the machine - a device that is off does not answer on the bus,
  as on a real УКНЦ without that board.

## What you need

- A Tang Nano 20K, a BL616 board (M0S Dock), a FAT32 SD card, a USB keyboard.
- Seven wires between the boards - the **stock MiSTeryNano pinout** (it was
  different before August 2026; an older board has to be rewired):

```
Tang Nano 20K   BL616
42              io10   MISO
41              io11   MOSI
56              io12   CSN
54              io13   SCK
51              io14   IRQ
GND             GND
+5              +5
```

I²S audio is on pins 71 (BCK), 72 (WS), 73 (DIN), 74 (amplifier enable);
HDMI carries the sound by itself.  The machine's serial port is on pins
69/70, which is the Tang's USB-C connector.

## How to flash

**BL616**, through its bootloader: hold **BOOT**, plug in USB (or press
**RST**), release BOOT; the board shows up as a serial port.  Then either
BLDevCube (chip BL616/BL618, MCU tab, file `bin/bl616.bin`, address
`0x00000000`, baud 2000000, Create & Download) or, from this repository:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

Press RST afterwards.

**Tang Nano 20K**, with openFPGALoader (or the Gowin Programmer):

```sh
openFPGALoader -b tangnano20k -f bin/tang.fs     # to flash
make flash-fpga-flash                            # the same from the repository
```

then **power-cycle the board**: after a write to flash it keeps running
the old bitstream until it is restarted.

## How to use it

The card goes into the Tang Nano 20K's slot: `.dsk` images (819 200
bytes) and `.img` files in any folder.  **F12** opens the menu; cursor
keys move, left and right step a value, Space or Enter selects, ESC
closes.  The first disk is `FDD0:` on the main page, then `Reset`; the
rest is under `Hardware`.  "Save settings" writes `/uknc.ini` to the
card.  The long version is `howto.md`.
