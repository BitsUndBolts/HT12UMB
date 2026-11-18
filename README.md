# HT12UMB – Upper Memory Blocks for Headland HT12 286 boards

By [Bits und Bolts](https://www.youtube.com/@bitsundbolts) · [bitsundbolts.com](https://bitsundbolts.com)

**HT12UMB.SYS** is a small DOS device driver that adds **64 KB of upper memory (UMB)**
to 80286 motherboards with the **Headland HT12 / HT12A** chipset. With it, `DOS=UMB`,
`DEVICEHIGH` and `LOADHIGH` work on a 286, with no 386 and no EMM386 needed.

It stays resident with 192 bytes and was written from scratch in NASM. No HT12 UMB
driver from the period is known to survive, so this one is new.

## Results

Octek FOX II 286, 4 MB RAM, MS-DOS 6.22:

|                           | Before   | With HT12UMB |
|---------------------------|----------|--------------|
| Free conventional memory  | 595 KB   | **622 KB**   |
| Upper memory              | 0 KB     | **64 KB** (C800–D7FF) |
| Loaded high               | –        | SETVER, SMARTDRV and other TSRs |

```
   C000-C7FF  video BIOS     RRRRRRRRRRRRRRRR
   C800-D7FF  HT12UMB        UUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUU
   F000-FFFF  system BIOS    RRRRRRRRRRRRRRRR
```

The full `MEM /C` and MSD reports are in [docs/measurements](docs/measurements).

## Why a 286 needs a special driver

On a 386, EMM386 creates UMBs with two CPU features:
- **Paging**, which maps RAM from above 1 MB into the free gaps between C000 and EFFF.
- **Virtual 8086 mode**, which lets DOS keep running while paging is on.

The 286 has neither feature. Any UMB on a 286 has to come from the chipset.

The HT12 has two ways to put RAM into the upper memory area:

1. **Shadow RAM**, one switch per 16 KB block. On the HT12 it is either readable
   (and write-protected) or writable (while reads go to the ROM/bus). It can never be
   both at once. We checked every register bit for a way around this; there is none.
   So shadow RAM can't hold UMBs. See [docs/HT12-REGISTERS.md](docs/HT12-REGISTERS.md).
2. **The EMS hardware**: four 16 KB windows that show any physical 16 KB page of DRAM,
   readable *and* writable. HT12UMB uses these.

## How it works

At boot, HT12UMB.SYS:

1. Checks for an HT12 chip and refuses to load if an EMS driver is present.
2. Finds the lowest free 64 KB area between C000 and EBFF. It checks for no ROM, no
   adapter RAM and no shadowing.
3. Points the four EMS windows at DRAM that is otherwise never visible. By default
   that is the DRAM behind A0000–AFFFF, pages 28h–2Bh.
4. Tests that RAM.
5. Hooks the XMS driver's entry point (HIMEM.SYS) and answers XMS functions **10h/11h**
   (request/release UMB). DOS asks for UMBs through these when `DOS=UMB` is set. This
   is the same approach UMBPCI uses on later chipsets.

## Limits

- **UMB or EMS, not both.** HT12UMB uses the same four windows as the EMS driver
  (HT12MM.SYS). Choose one at boot, for example with a CONFIG.SYS menu.
- **64 KB maximum.** The chip has exactly four windows of 16 KB.
- Tested on one board only: Octek FOX II rev 3.4, HT12/A, AMI BIOS 06/13/90,
  MS-DOS 6.22 with HIMEM.SYS 3.10. It should work with MS-DOS 5 and other HT12
  boards, but that is untested. Reports are welcome.

## Install

```
DEVICE=C:\DOS\HIMEM.SYS
DEVICE=C:\HT12\HT12UMB.SYS
DOS=HIGH,UMB
DEVICEHIGH=C:\DOS\SETVER.EXE
```

HT12UMB must load **after** HIMEM.SYS and **without** HT12MM.SYS.
Then use `DEVICEHIGH=` in CONFIG.SYS and `LH` in AUTOEXEC.BAT. Programs like
SMARTDRV load high on their own.

**BIOS EMS size:** HT12UMB doesn't need it. Any memory the BIOS sets aside as EMS is
lost to XMS while HT12UMB is loaded. For a UMB-only setup, set EMS to 0 in the BIOS.
If you also want an EMS boot option, keep BIOS EMS at 0 and give HT12MM.SYS
`/EXTENDED=nnnn` instead.

### Options

| Option | Meaning |
|---|---|
| `/F=xxxx` | frame segment, C000…DC00 in 400h steps (default: lowest free) |
| `/P=xx`   | first physical 16 KB DRAM page for the four windows (default 28h) |
| `/T`      | skip the RAM test |

Example banner:
```
HT12UMB 1.0 - UMB driver for the Headland HT12 (Bits und Bolts 2026)
  64K upper memory at C800-D7FF, DRAM pages 28-2Bh. Use DOS=UMB.
```

## Build

Requires [NASM](https://nasm.us). Run `BUILD.BAT`, or:
```
nasm -f bin -o bin\HT12UMB.SYS src\HT12UMB.ASM
nasm -f bin -o tools\htprobe\HTPROBE.COM tools\htprobe\HTPROBE.ASM
```
The sources use 286 instructions only.

## HTPROBE – register test tool

`HTPROBE ii vv ssss` sets HT12 register `ii` to `vv` for a few microseconds, with
interrupts off. During that time it writes a test pattern to `ssss:0010`, then
restores the register. It reports what was read before the write, during the test
state, after the write and after the restore. We used it to test risky bits
without crashing the machine.

> Careful: some bits (e.g. reg 14h bit 3, or the DRAM layout in reg 10h) can hang the
> board if left changed. HTPROBE always restores them, but use it at your own risk.

## Files

```
src/HT12UMB.ASM              driver source
bin/HT12UMB.SYS              driver, ready to use
tools/htprobe/               register probe tool (source + .COM)
docs/HT12-REGISTERS.md       HT12 register map as far as we know it
docs/measurements/           MEM /C and MSD reports:
  1_BASE_*                     stock setup (no EMS, no UMB)
  2_EMS_*                      HT12MM.SYS EMS driver (1312 KB EMS, frame C800)
  3_UMB_*                      HT12UMB.SYS (64 KB UMB)
BUILD.BAT                    build script
```

## Credits

- Made for a [Bits und Bolts](https://www.youtube.com/@bitsundbolts) video
  ([bitsundbolts.com](https://bitsundbolts.com)). The
  development and all tests ran on the real board, controlled remotely through DOSAI.
- The HT12 EMS driver HT12MM.SYS (Quadtel, 1991) is not included. It can be
  downloaded from [dosdays.co.uk](https://www.dosdays.co.uk/topics/Manufacturers/headland.php).
- The [VOGONS thread on HT12/A UMBs](https://www.vogons.org/viewtopic.php?p=585069)
  documented the earlier attempts with The Last Byte.
