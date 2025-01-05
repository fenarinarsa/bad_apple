

VASM = vasm -Ftos -devpac
LZ4 = lz4.exe

all: ankha.tos

ankha.tos: ankha.s small ankha.pal
	$(VASM) -o ankha.tos ankha.s
#	copy ankha.tos Q:\DEV\ANKHA\ANKHA.TOS
	cp ankha.tos ..\..\ANKHA.TOS

clean:
	rm ankha.tos

	