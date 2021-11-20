

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ankha.tos

ankha.tos: ba.s small
	$(VASM) -o ankha.tos ba.s
	copy ankha.tos ..\..\

clean:
	del ankha.tos

	