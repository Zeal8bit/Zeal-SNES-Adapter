CC=z88dk-z80asm
BIN=snes.bin
DUMP=$(basename $(BIN)).dump
MAP=$(basename $(BIN)).map
SRCS=snes_demo.asm

.PHONY: all clean dump

all: 
	$(CC) -o$(BIN) -m -b $(SRCS)

dump:
	z88dk.z88dk-dis -o 0x4000 -x $(MAP) $(BIN) > $(DUMP)

clean:
	rm -f $(BIN) *.o *.map *.dump
