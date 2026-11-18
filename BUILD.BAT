@ECHO OFF
REM Builds HT12UMB.SYS and HTPROBE.COM with NASM (https://nasm.us)
nasm -f bin -o bin\HT12UMB.SYS src\HT12UMB.ASM
IF ERRORLEVEL 1 GOTO END
nasm -f bin -o tools\htprobe\HTPROBE.COM tools\htprobe\HTPROBE.ASM
:END
