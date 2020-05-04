

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ba.tos

ba.tos: ba.s small
	$(VASM) -o ba.tos ba.s

clean:
	del ba.tos

	