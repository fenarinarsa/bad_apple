# Bad Apple!!

Bad Apple!! for Atari STE

The infamous video for your STE.

**music:** Masayoshi Minoshima (Alstroemeria Records)  
**vocals** nomico  
**original video** Anira  
**code:** Fenarinarsa  

**Binaries & videos**  
https://demozoo.org/productions/180988/

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


# Contents

- asm  
Contains the player in 68000 assembler code for Atari STE.

- BASTGenerator  
Data files generator in C#. To regenerate the files you'll also need the audio/video assets available here:  
https://fenarinarsa.com/badapple/fenarinarsa_badapple_source.zip  
...and Visual Studio (any edition).


# Build instructions

You need the following tools:  
- vasm (cross-platform) or Devpac (ST)  
- make (the GNU/Linux tool)  

## vasm

For Windows I offer you my vasm 1.8 binary here (else you need to compile it from source code):  
https://fenarinarsa.com/demos/vasm_mot_1.8.zip  
Official site with source code:  
http://sun.hasenbraten.de/vasm/

And add vasm's path to the environment PATH variable. 

## make

The fastest way to install make on Windows is to install chocolatey:  
https://chocolatey.org/  
Then open a shell as administrator and type:  
`choco install make`

## Build

To build ba.tos, open a shell, go to the "asm" folder and type:  
`make`

You will get a ba.tos that works with the 50kHz color version.

The data files can be found in the final release:  
https://fenarinarsa.com/badapple/fenarinarsa_badapple_final.zip

## Options

You can switch to monochrome by setting ```monochrome EQU 1``` at the start of the source code.  

The DMA sound frequency can be easily changed (look for ```move.b #%11,$FFFF8921.w```).  

It's worth noting that you can disable the blitter use in BASTGenerator by setting all three ```opt_blitter``` options to ```false``` in ```bw_MakeRun()```. The generated data file will only contain software code for delta-packing without any need to change the player. By using ony 8 greyshades and adding a software YM2149 sample replay, an STF version should be possible.  

A Falcon version could also be done by removing all audio data and using an MP2 player.

