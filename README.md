# Bad Apple!!

Bad Apple!! for Atari STE

The infamous video for your STE.

**music:** Masayoshi Minoshima (Alstroemeria Records) 
**vocals** nomico 
**original video** Anira 
**code:** Fenarinarsa 

**Web** 
https://fenarinarsa.com  

**Twitter**  
https://twitter.com/fenarinarsa  

**Mastodon**  
https://shelter.moe/@fenarinarsa


# Requirements

Atari STE or Mega STE with at least 1MB RAM
Color or monochrome monitor
ACSI or IDE Hard Drive


## Folders
# asm
Contains the player in 68000 assembler code for Atari STE.

# BASTGenerator
Data files generator in C#. To regenerate the files you'll also need the audio/video assets available here: 
https://fenarinarsa.com/badapple/fenarinarsa_badapple_source.zip 
...and Visual Studio (any edition).


## Building instructions

You need the following tools:  
- vasm or Devpac  
- make (the GNU/Linux tool)  

### vasm

For Windows I offer you my vasm 1.8 binary here (else you need to compile it from source code): 
https://fenarinarsa.com/demos/vasm_mot_1.8.zip 
Official site with source code: 
http://sun.hasenbraten.de/vasm/

### make

The fastest way to install make is to first install chocolatey: 
https://chocolatey.org/ 
Then open a shell as administrator and type: 
choco install make

Then add vasm's path to the environment PATH variable. 

### Build

To build ba.tos, open a shell, go to the "asm" folder and type: 
make

You will get a ba.tos that works with the 50kHz color version. 

The data files can be found in the final release: 
https://fenarinarsa.com/badapple/fenarinarsa_badapple_final.zip







