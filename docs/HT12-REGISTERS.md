# Headland HT12/A registers – what we found

Everything here was measured on one board: Octek FOX II rev 3.4 with a
Headland HT12/A, AMI BIOS 06/13/90, 4 MB RAM (4 × 1 MB SIMMs). Sources are:
- the BIOS's own chipset code
- the Quadtel EMS driver HT12MM.SYS 4.00 (disassembled)
- tests on the running board with [HTPROBE](../tools/htprobe/HTPROBE.ASM)

Anything still unknown is marked as unknown.

## Access

| Port | Use |
|---|---|
| 1EDh | index (readable – reads back the last index written) |
| 1EFh | data of the selected register |

```asm
mov dx,1EDh
mov al,index
out dx,al
mov dx,1EFh
in  al,dx        ; or: out dx,al
```

Registers that exist: **10h–19h** and **20h–23h**. Indexes 00h–0Fh, 1Ah–1Fh and 24h–FFh
read 00h and ignore writes (they are not mirrors of the real ones).

## Power-up values

The BIOS (F000:F104 in the 06/13/90 BIOS) writes this table at boot:
`10h=0Eh 12h=00h 13h=00h 14h=18h 18h=3Fh`. It then adjusts some bits. Values seen at
the DOS prompt on this board:

| Reg | Value | Meaning |
|---|---|---|
| 10h | 3Eh | DRAM config 6 = 1M/1M + fixed bits 3–5 |
| 12h | 03h | C000–C7FF shadowed (video BIOS) |
| 13h | F0h | F000–FFFF shadowed (system BIOS) |
| 14h | 1Ah | shadow read on + bits 3, 4 |
| 15h | 03h | read-only, meaning unknown |
| 17h | 10h | read-only revision (HT12MM checks high nibble = 1) |
| 18h | 3Fh / 2Fh | top of extended memory (BIOS EMS 0 / 1024 KB) |
| 19h | 00h | EMS off |

**A warm reboot does not reset regs 19h–23h.** Whatever an EMS driver left there stays
active until the reset button is pressed or a driver reprograms them.

## Register details

### 10h – DRAM configuration
- bits 0–2: bank layout: 1 = 256K/–, 2 = 256K/64K, 3 = 256K/256K, 4 = 256K/1M,
  5 = 1M/–, 6 = 1M/1M. **Don't touch while running.**
- bits 3–5: always set by the BIOS. Changing them for a moment had no visible effect.
- bits 6–7: writable, unused by the BIOS, no effect found.

### 11h, 15h, 16h, 17h
- 11h and 16h read 00h and keep no written bit.
- 15h reads 03h and is read-only. It does not follow reg 12h.
- 17h reads 10h and is read-only (revision/status). The BIOS tests bit 4 to pick
  one of two init tables.

### 12h / 13h – shadow RAM, one bit per 16 KB block

| Reg | bit 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| 12h | C000 | C400 | C800 | CC00 | D000 | D400 | D800 | DC00 |
| 13h | E000 | E400 | E800 | EC00 | F000 | F400 | F800 | FC00 |

Confirmed: setting 13h bit 0 affects E000–E3FF and nothing else.

### 14h – shadow mode and memory decode

| Bit | Effect |
|---|---|
| 1 | **0:** reads of shadowed blocks come from ROM / ISA bus, writes go into the shadow DRAM.<br>**1:** reads come from the shadow DRAM, **writes are ignored**. This applies to all blocks at once. |
| 2 | memory relocation. The BIOS only sets it for a 256K/256K layout. HT12MM then offers all 24 hole pages (A000–FFFF) as EMS. |
| 3 | must stay 1. Clearing it froze the board after a short time (refresh?). For microseconds it is harmless. |
| 4 | 0 = the BIOS ROM sockets also answer at E0000–EFFFF (for 128K BIOS ROMs). |
| 0, 5, 6, 7 | writable, no effect on shadow reads or writes found |

**There is no setting in which shadow RAM can be read and written at the same time.**
That is why shadow RAM cannot be used for UMBs on this chipset.

### 18h – top of extended memory
Value = (top of extended memory in 64 KB units) − 1. 3Fh = 4 MB, 2Fh = 3 MB. Memory
above that is EMS. When EMS is set in the BIOS, the BIOS writes `CMOS[B5h] − CMOS[B6h] + 0Fh`; otherwise it stays at 3Fh.
HT12MM.SYS reprograms it when you use `/EXTENDED=`.

### 19h – EMS control

| Bits | Effect |
|---|---|
| 0–3 | window 0–3 enable |
| 4–6 | frame start = C000h + n × 400h (n = 0…7 → C000 … DC00). HT12MM only offers n = 0…4. n = 7 (DC00–EBFF) works. |
| 7 | EMS on |

The four 16 KB windows always sit at frame +0, +16K, +32K and +48K.

### 20h–23h – EMS window pages
The **absolute physical 16 KB page number** shown in window 0–3:
page × 16 KB = physical address. Pages 28h–3Fh are the DRAM that sits hidden behind
A0000–FFFFF. Example: page 38h shows the DRAM behind E0000.
The windows can be read **and written**. HT12UMB.SYS is built on this.
