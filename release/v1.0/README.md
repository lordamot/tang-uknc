# UKNC Nano v1.0 - the original release / оригинальный выпуск

**English below.**

## Русский

Это **оригинальные** прошивки UKNC Nano - МС0511 (УКНЦ) на Tang Nano 20K
с платой BL616 - в том виде, в каком их выпустил автор аппаратной части
**Алексей Гуров** (сборка ПЛИС - январь 2025, прошивка МК - август 2024).
Они выложены здесь как отправная точка, версия 1.0; всё, что сделано
после, - линия 2.x (`VERSION`, `CHANGELOG.md` в корне репозитория).

| файл | размер | что это |
|---|---|---|
| `tang.fs` | 7 261 987 | прошивка ПЛИС для Tang Nano 20K (`openFPGALoader -b tangnano20k -f tang.fs`) |
| `bl616.bin` | 399 808 | прошивка МК для платы BL616 (M0S Dock), через её загрузчик |

**Обратите внимание: распиновка этой версии - авторская, а не та, что у
исходного проекта MiSTeryNano и у версий 2.x.**  Плата, собранная под
2.x, с этими прошивками работать не будет, и наоборот.

```
Tang Nano 20K    BL616
71               io12
72               io13
73               io10
74               io11
75               io14
GND              GND
+5               +5
```

Меню: F12.  Образы дискет - файлы `.dsk` по 819 200 байт на SD-карте
(FAT).  Что именно умеет эта версия и чего не умеет, описано в
`.claude/docs/progress.md` репозитория, в разделах о состоянии до
августа 2026 года; исходники - коммит `0ab368e` (`git checkout v1.0`).

## English

These are the **original** UKNC Nano binaries - the МС0511 (УКНЦ) on a
Tang Nano 20K with a BL616 board - exactly as the hardware's author,
**Alexey Gurov**, released them (FPGA build January 2025, MCU firmware
August 2024).  They are kept here as the starting point, version 1.0;
everything done since is the 2.x line (`VERSION` and `CHANGELOG.md` at
the repository root).

| file | size | what it is |
|---|---|---|
| `tang.fs` | 7 261 987 | the FPGA bitstream for the Tang Nano 20K (`openFPGALoader -b tangnano20k -f tang.fs`) |
| `bl616.bin` | 399 808 | the MCU firmware for the BL616 board (M0S Dock), through its bootloader |

**Be careful: this version is wired the author's way, not the way the
stock MiSTeryNano project and the 2.x versions are.**  A board wired for
2.x will not work with these binaries, and the other way round.

```
Tang Nano 20K    BL616
71               io12
72               io13
73               io10
74               io11
75               io14
GND              GND
+5               +5
```

The menu is F12.  Disk images are `.dsk` files of 819 200 bytes on a FAT
SD card.  What this version does and does not do is in the repository's
`.claude/docs/progress.md`, the parts about the state before August 2026;
the sources are commit `0ab368e` (`git checkout v1.0`).
