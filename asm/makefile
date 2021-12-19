

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ankha.tos

ankha.tos: ba.s small ankha.pal
	$(VASM) -o ankha.tos ba.s
	copy ankha.tos Q:\DEV\ANKHA\ANKHA.TOS

clean:
	del ankha.tos

	