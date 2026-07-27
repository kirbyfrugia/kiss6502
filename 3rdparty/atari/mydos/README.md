# MyDOS boot files

These are not bundled. Drop MyDOS `DOS.SYS`, `DUP.SYS`, and a `boot.bin`
(the MyDOS boot sectors) in this directory, or point `ATARI_DOS_DIR` at a
directory that has them:

    make atari ATARI_DOS_DIR=/path/to/mydos
