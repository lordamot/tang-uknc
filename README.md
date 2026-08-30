# UKNC FPGA

Мы рады представить UKNC FPGA.

Автор - Алексей Гуров.

Вам потребуется:
- tang20nano
- bl616 board
- свежий PC с USB интерфейсом

## ОБРАТИТЕ ВНИМАНИЕ

Распиновка теперь как в исходном репозитории MiSTeryNano.
До августа 2026 года она была другой - если у вас плата,
разведённая по старой таблице, её нужно переразвести:
переехала не только связь с МК, но и звук.

```
tang20nano    bl616
42            io10     MISO
41            io11     MOSI
56            io12     CSN
54            io13     SCK
51            io14     IRQ
GND           GND
+5            +5
```

Звук (I2S) теперь на выводах 71 BCK, 72 WS, 73 DIN,
74 разрешение усилителя.  Последовательный порт - 48 выход,
55 вход.  Подробности в `howto-ru.md`, раздел 2.

---

We are proud to share this product of Alex Gurov.

Prereqs:
- tang20nano
- bl616 board
- recent PC with USB interface

## BE CAREFUL

The pinout is now the stock MiSTeryNano one.  It was not
before August 2026 - if your board is wired from the old
table it has to be rewired, and not only the MCU link
moved: the audio moved too.

```
tang20nano    bl616
42            io10     MISO
41            io11     MOSI
56            io12     CSN
54            io13     SCK
51            io14     IRQ
GND           GND
+5            +5
```

Audio (I2S) is now on 71 BCK, 72 WS, 73 DIN, 74 amplifier
enable.  Serial is unchanged on 69 out, 70 in - the Tang's
own BL616, so the console is the USB-C port.  Details in
`howto.md`, section 2.
