
* ANKHA Atari STE version (color)
* Copyright (C) 2017-2021 fenarinarsa (Cyril Lambin)
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <https://www.gnu.org/licenses/>.


* Credits
* Original video: ZONE (ZONE-ARCHIVE.COM), used with authorization
* Music: Camel by Camel by Sandy Marton
* Atari STE version by fenarinarsa
*
* Based on the BAD APPLE!! player released in 2017, modified to work under steroids.
*
* Compiled using vasm, but can also be build using devpac.
*
* How does this work?
*   It reads a data file that contains multiplexed audio and video frames, just like a video.
*   The difference is the video frames can contain code and/or blitter data.
*   A buffer the size of available RAM is set up, then the file is read in this buffer in a cyclic way (it's a FIFO buffer)
*   VBL is used to count frames
*   Timer B is used to enable HBL at the bottom of visible picture
*   HBL contains the actual graphic render code and sets up the audio DMA & video buffers (that way it can be interrupted by VBL)
*   The loading may occur during rendering because the ACSI DMA transfers, once started, will interrupt the CPU and the blitter if needed.
*   Some drivers (maybe all of them) also disable Mega STE cache when loading.
*
* How to make this Atari ST compatible?
*   Video buffers should be set on a memory adress multiple of $100 and $ffff820d of course not used
*   The runtime file must be generated with a lower audio quality and no blitter optimization (see the C# generator options)
*     also: only 3 bitplanes are needed since the ST has only 8 shades of grey, which is a lot less BDSM fun.
*   A soft audio replay rout must be written.
*
* How to make this Falcon030 compatible?
*   The main incompatibility point may be the way the HBL is enabled, by modifying the stack in "tb_render".
*   This may work: enable HBL all the time, and in "hbl" quit immediatly if a render switch is not on;
*                activate this switch in tb_render
*
* How to make this TT compatible?
*   This may work: do the same than for Falcon030, then set "blitter" to 0 at the start of this file to use the blitter emulation.
*                also the video buffers should be set on a memory adress multiple of $100 like for Atari ST.
*
* Note that in both cases generated code is loaded from file, so I don't know how the 68030 cache would handle that.
* Also, better save/inits/restore of interrupts/chipset state may be needed.
* And finally the runtime file must be generated with the correct video frequencies so the audio is correctly muxed.
*
* Don't hesitate to donate a Falcon030 or a TT so I can do a compatible version :D
*
* Any complain of badly written "it looks like 30 years old" code can be sent to
* Twitter @fenarinarsa
* Mastodon @fenarinarsa@shelter.moe
* Web fenarinarsa.com

	;opt d+

emu	EQU	0	; 1=emulate HDD access timings by adding NOPs
ram_limit	EQU	0	; 0=no limit, other=malloc size
blitter	EQU	1	; 1=use blitter 0=emulate blitter (not complete, for debug purpose only)
minimum_load EQU	512*400	; minimum size of a disk read (to optimize FREADs)
loop_play	EQU	1
monochrome EQU 0

line_length EQU 	160
horz_shift	 EQU	1
intro_shift EQU	0
vbl_per_frame EQU	2	; 25fps
nb_frames	EQU	3828	; number of frames in file
loop_frame EQU	992

	; uses a6
AUDIO_DMA_SET	MACRO
	lea	$ffff8900.w,a6
	swap	\2
	move.b	\2,$0F(a6)
	swap	\2
	movep.w	\2,$11(a6)
	swap	\1
	move.b	\1,$03(a6)
	swap	\1
	movep.w	\1,$05(a6)
	ENDM

EMU_HDD_LAG	MACRO	
	IFNE	emu
	move.l	d6,d5
.wait_emu	nop
	nop
	nop
	dbra.s	d5,.wait_emu
	ENDC
	ENDM

START_PLAYING	MACRO
	move.w	vbl_count,next_refresh
	clr.w	b_buffering_lock	; enable play if previously disabled
	move.b	#%11,$ffff8901.w	; restart sound
	ENDM


COLOR_DEBUG	MACRO
	
	tst.w	debug_color
	beq.s	.\@
	IFEQ	monochrome
	move.w	#\1,$ffff8240.w
	ELSE
	not.w	$ffff8240.w
	ENDC
.\@
	ENDM

	; check if the monitor fits the replay mode (color or monochrome)
	move.w	#4,-(sp)     ; getrez
	trap	#14
	addq.l	#2,sp
	cmp.w	#2,d0
	bge	error_needscolor

	*** Mshrink
	movea.l   4(sp),a5
	move.l    12(a5),d0
	add.l     20(a5),d0
	add.l     28(a5),d0
	addi.l    #$1100,d0
	move.l    d0,d1
	add.l     a5,d1
	andi.l    #-2,d1
	movea.l   d1,sp
	move.l    d0,-(sp)
	move.l    a5,-(sp)
	clr.w     -(sp)
	move.w    #$4a,-(sp)
	trap      #1
	lea       12(a7),a7

	*** SUPER
	clr.l	-(sp)
	move.w	#$20,-(sp)		; super
	trap	#1
	addq.w	#6,sp

	*** get the biggest available block in memory for the file buffer
	move.l	#-1,-(sp)
	move.w	#$48,-(sp)		; malloc
	trap	#1
	addq.l	#6,sp
	cmp.l	#3*minimum_load,d0	; needs at least 3*minimum_load of free RAM
	blt	buyram		; stop if not enough memory
	IFNE	ram_limit
	move.l	#ram_limit,d0	; limit used RAM (debug)
	ENDC
	move.l	d0,vid_buffer_end
	move.l	d0,-(sp)
	move.w	#$48,-(sp)		; malloc
	trap	#1
	addq.l	#6,sp
	tst.l	d0
	ble	end		; error while doing malloc
	move.l	d0,vid_buffer
	add.l	d0,vid_buffer_end
	move.l	d0,play_ptr
	move.l	d0,aplay_ptr
	addq	#2,d0
	move.l	d0,load_ptr	; add 2 to load_ptr because it must be >play_ptr, else it means the buffer is full

	*** Open index file
	move.w	#0,-(sp)		; open index
	pea	s_idx_filename
	move.w	#$3D,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.w	d0
	ble	file_error	; index not found

	move.w	d0,file_handle

	*** Read index
	pea	vid_index
	move.l	#(nb_frames*2),-(sp)		; read index
	move.w	file_handle,-(sp)
	move.w	#$3F,-(sp)
	trap	#1
	add.l	#12,sp
	cmp.w	#4,d0		; error file too short
	ble	file_error

	*** Close index file
	move.w	file_handle,-(sp)	; close index
	move.w	#$3e,-(sp)		
	addq.l	#4,sp
	
	*** Open runtime file
	move.w	#0,-(sp)		; open video
	pea	s_vid_filename
	move.w	#$3D,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.w	d0
	ble	file_error		; video not found

	move.w	d0,file_handle

	move.w	#2,-(sp)		; physaddr
	trap	#14
	move.l	d0,old_screen



*** Hardware inits
hwinits
	moveq	#$12,d0
	jsr	ikbd		; turn off mouse
	moveq	#$15,d0
	jsr	ikbd		; turn off joysticks
	jsr	flush

	move.w	#$2700,sr

	movem.l	$ffff8240.w,d0-d7
	movem.l	d0-d7,old_palette

	move.b	$ffff8260.w,old_rez
	move.b	$ffff820a.w,old_hz
	moveq	#0,d5		; reset vbl counter

	lea	old_ints,a0
	move.l	$68.w,(a0)+
	move.l	$70.w,(a0)+
	move.l	$118.w,(a0)+
	move.l	$120.w,(a0)+
	move.b	$fffffa07.w,(a0)+
	move.b	$fffffa09.w,(a0)+
	move.b	$fffffa0f.w,(a0)+
	move.b	$fffffa11.w,(a0)+
	move.b	$fffffa13.w,(a0)+
	move.b	$fffffa15.w,(a0)+
	move.b	$fffffa17.w,(a0)+
	move.b	$fffffa1b.w,(a0)+
	move.b	$fffffa21.w,(a0)+

	sf	$fffffa19.w	; stop timer A
	sf	$fffffa1b.w	; stop timer B
	move.l	#dummy_rte,$70.w	; temporary vbl
	move.l	#dummy_rte,$68.w	; temporary hbl

	move	#$2300,sr
	stop	#$2300	; wait for vbl
	bset.b	#1,$ffff820a.w	; 50Hz
	clr.b	$ffff8260.w	; lowrez
	move.w	#$2700,sr

	; STE pal
	lea	palette,a0
	jsr	convert_palette_ste
	movem.l	palette,d0-d7
	movem.l	d0-d7,$ffff8240.w

	move.l	#vbl,$70.w
	move.l	#hbl,$68.w

	; Timer C should not be stopped because it's used by some HDD drivers
	move.b	#%00100001,$fffffa07.w	; timer a/b only
	and.b	#%11100000,$fffffa09.w	; all but timer C / ACIA / HDC controller
	or.b	#%01000000,$fffffa09.w	; enable ACIA
	move.b	#%00100001,$fffffa13.w	; timer a/b only
	and.b	#%11100000,$fffffa15.w	; all but timer C & ACIA / HDC controller
	or.b	#%01000000,$fffffa15.w	; enable ACIA
	bclr	#3,$fffffa17.w

	move.w	#$2300,sr

	move.b	screen_display_ptr+1,$ffff8201.w
	move.b	screen_display_ptr+2,$ffff8203.w
	move.b	screen_display_ptr+3,$ffff820d.w

	move.b     #%10,$FFFF8921.w	; 25kHz stereo
	;move.b     #%10000001,$FFFF8921.w	; 12kHz mono
	move.l	#buf_nothing,d0
	move.l 	#buf_nothing_end,d1
	AUDIO_DMA_SET d0,d1
	move.b	#%11,$ffff8901.w	; start playing sound

	; enable Timer A
	move.l	#timer_a,$134.w
	move.b	#1,$fffffa1f.w
	move.b	#8,$fffffa19.w

	move.w	vbl_count,d0
	addq	#2,d0
	move.w	d0,next_refresh

	; clear screen buffers
	move.l	screen_display_ptr,a0
	moveq	#0,d0
	move.w	#7999,d1
.clr1	move.l	d0,(a0)+
	dbra.s	d1,.clr1
	move.l	screen_render_ptr,a0
	move.w	#7999,d1
.clr2	move.l	d0,(a0)+
	dbra.s	d1,.clr2

*** MAIN LOOP
* the main loop is where the loading takes place
* with a FIFO (cyclic) buffer
* meanwhile rendering takes place in the HBL interrupt

next_frame
	; read next frame from file
next_load	
	move.l	idx_load,a0
	tst.w	(a0)		; end of index
	bne.s	find_load_size

	IFEQ loop_play
	; we're done loading, force play until the end of video
	bra	wait_for_play_end

	ELSE
	; end of file, looping video
	move.l	idx_loaded,a0	; set -1 at the end of the loaded data ptr list
	move.l	#-1,(a0)
	move.l	#play_index,idx_loaded
	move.l	#vid_index,a0
	move.w	#loop_frame-1,d0
	; add intro's frame sizes to get the loop frame offset in file
	move.w	#0,a1
.findloopindex
	adda.w	(a0)+,a1
	dbra	d0,.findloopindex
	move.l	a0,idx_load
	; seek to start of file
	clr.w	-(sp)
	move.w	file_handle,-(sp)
	move.l	a1,-(sp)		; seek offset
	move.w	#66,-(sp)		; fseek
	trap	#1
	add.l	#10,sp
	move.l	idx_load,a0
	ENDC	

find_load_size
	moveq	#0,d5
	moveq	#0,d6		; d6 = size to load
	moveq	#-1,d7		; d7 = number of frames we are going to load
.checksize	move.w	(a0)+,d5
	beq	check_room		; nul => EOF
	add.l	d5,d6
	addq	#1,d7
	cmp.l	#minimum_load,d6	; load a minimum of big chunk of data to avoid the most GEMDOS memory copies possible
	blt.s	.checksize

check_room	
	bsr	check_ikbd
	move.l	load_ptr,a0
	move.l	play_ptr,a1
	move.w	play_frm,d0
	cmp.w	aplay_frm,d0	; if (play_frm < aplay_frm) => a1=play_ptr
	blt.s	.oklimit
	move.l	aplay_ptr,a2
	cmp.l	#buf_nothing_end,a2
	ble.s	.oklimit
	move.l	a2,a1
.oklimit	move.l	vid_buffer_end,a2	; a2=upper limit (default=end of filebuffer)

	move.l	a0,a3
	add.l	d6,a3		; a3=end_load_ptr

	cmp.l	a1,a0		; if (load_ptr <= play_ptr) => .upper_is_play
	ble.s	.upper_is_play
	cmp.l	a2,a3		; if (end_load_ptr <= vid_buffer_end) => loading
	ble	loading

	move.l	vid_buffer,a0	; load_ptr = start of vid buffer (looping memory)
	move.l	a0,load_ptr	
	move.l	a0,a3
	add.l	d6,a3

.upper_is_play
	cmp.l	a1,a3		; if (end_load_ptr < play_ptr) => loading
	blt	loading

.bufferfull
	; not enough room to load anything (buffer full)
	tst.w	b_buffering_lock
	beq.s	check_room		; we're not in buffering mode, recheck now

exit_buffering
	; exit buffering mode
	START_PLAYING
	bra	check_room

check_ikbd	cmp.b	#$1+$80,$fffffc02.w	; ESC depressed
	bne	.no_esc
	addq	#4,sp
	bra	video_end
.no_esc	clr.w	debug_color
	cmp.b	#$4e+$80,$fffffc02.w  ; + depressed
	bne.s	.noplus
	move.w	#-1,debug_info
	bsr	.endcheck
.noplus	cmp.b	#$4a+$80,$fffffc02.w  ; - depressed
	bne.s	.nominus
	clr.w	debug_info
	bsr	.endcheck
.nominus	cmp.b	#$2a,$fffffc02.w	; Left-shift pressed
	bne.s	.endcheck
	move.w	#-1,debug_color
.endcheck	rts

	

loading	move.w	#-1,b_loading
	move.l	load_ptr,-(sp)
	move.l	d6,-(sp)
	move.w	file_handle,-(sp)
	move.w	#$3F,-(sp)		; fread
	;COLOR_DEBUG $400	; faint red
	EMU_HDD_LAG
	trap	#1
	;COLOR_DEBUG $000	; black
	add.l	#12,sp
	clr.w	b_loading

	; filling idx_loaded with updated play pointers
	; idx_load: 16 bits frame size list, from original ".idx" file
	; load_ptr: ptr to the data that has just been loaded
	; idx_loaded: 32 bits ptr list generated from idx_load and load_ptr
	moveq	#0,d0
	move.l	idx_loaded,a0
	move.l	idx_load,a1
	move.l	load_ptr,a2
.idxloop	move.l	a2,(a0)+
	move.w	(a1)+,d0
	add.l	d0,a2
	dbra.s	d7,.idxloop
	move.l	a2,load_ptr
	move.l	a1,idx_load
	move.l	a0,idx_loaded

	cmp.l	#buf_nothing,a0	; assert (idx_loaded) < buf_nothing
	ble.s	.okaydebug
	bra	video_end	; error
.okaydebug

	; purple
	;move.w	#$707,d0
	;moveq	#15,d1
	;bsr	debug

	tst.w	b_first_load
	beq	next_load		; not first refresh: loading next frames if possible

	; start video (first refresh) directly after first load
	; start rendering without waiting for the buffer to be full
	; we can do that with ANKHA since the intro is very light
	clr.w	b_first_load
	START_PLAYING
	bra	next_load

	IFEQ	loop_play
wait_for_play_end
	move.w	vbl_count,next_refresh
	clr.w	b_buffering_lock	; enable play if previously disabled
	move.b	#%11,$ffff8901.w	; restart sound if previously disabled
	move.l	idx_loaded,a0	; set -1 at the end the loaded data ptr list
	move.l	#-1,(a0)
.wait	bsr	check_ikbd
	move.l	idx_play,a0	; if -1 we reached the end of the loaded frames
	tst.l	(a0)
	bge.s	.wait
	ENDC

*** END

video_end	
	*** Close video file
	move.w	file_handle,-(sp)
	move.w	#$3e,-(sp)
	addq.l	#4,sp

	*** Hardware restore
	move.w	#$2700,sr

	clr.w	$ffff8900.w	; stop playing sound

	sf	$fffffa19.w	; stop timer A
	sf	$fffffa1b.w	; stop timer B
	move.l	#dummy_rte,$70.w	; temporary vbl
	move.l	#dummy_rte,$68.w	; temporary hbl
	move.w	#$2300,sr		; wait for vbl
	movem.l	old_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w
	move.b	old_rez,$ffff8260.w
	move.b	old_hz,$ffff820a.w
	move.b	old_screen+1,$ffff8201.w
	move.b	old_screen+2,$ffff8203.w
	move.b	old_screen+3,$ffff820d.w
	move.w	#$2700,sr

	lea	old_ints,a0
	move.l	(a0)+,$68.w
	move.l	(a0)+,$70.w
	move.l	(a0)+,$118.w
	move.l	(a0)+,$120.w
	move.b	(a0)+,$fffffa07.w
	move.b	(a0)+,$fffffa09.w
	move.b	(a0)+,$fffffa0f.w
	move.b	(a0)+,$fffffa11.w
	move.b	(a0)+,$fffffa13.w
	move.b	(a0)+,$fffffa15.w
	move.b	(a0)+,$fffffa17.w
	move.b	(a0)+,$fffffa1b.w
	move.b	(a0)+,$fffffa21.w
	move.b	#$c0,$fffffa23.w	; fix key repeat

	move.w	#$2300,sr

	moveq	#$8,d0
	jsr	ikbd		; turn on mouse
	jsr	flush

	clr.l	-(sp)
	move.w	#$20,-(sp)		; super
	trap	#1
	addq.w	#6,sp

end	; PTERM
	clr.w	-(sp)
	trap #1


*** GRAPHIC AND SOUND RENDER
* Audio is played from loaded raw data
* Frame is rendered by running the generated code + blitter data loaded from file
* VBL only prints debug data

vbl	addq.w	#1,vbl_count
	; enable Timer B at line 199
	; which will fire HBL in return
	sf	$fffffa1b.w
	IFEQ	monochrome
	move.l	#tb_render,$120.w
	ELSE
	move.l	#tb_mono,$120.w
	ENDC
	move.b	#199,$fffffa21.w
	move.b	#8,$fffffa1b.w

vbl_debug	move.w	$ffff8240.w,-(sp)
	COLOR_DEBUG $555

	movem.l	d0-a6,-(sp)

	tst.w	debug_info
	bne.s	.print_debug

	;end debug info

.nodebug	
	; check for palette change
	move.l	pal_ptr,a0
	move.w	(a0),d0
	addq	#2,d0
	cmp.w	play_frm,d0
	bne.s	.nopalchange
	lea	34(a0),a0		; next palette
	move.l	a0,pal_ptr
.nopalchange
	movem.l	-32(a0),d0-d7	; setup palette for this frame
	movem.l	d0-d7,$ffff8240.w

	movem.l	(sp)+,d0-a6
	tst.w	debug_color
	bne.s	.endvblcolor
	addq	#2,sp
	rte
.endvblcolor
	move.w	(sp)+,$ffff8240.w
	rte

.print_debug
	; print debug info
	move.l	screen_debug_ptr,a1

	; "LOAD"
	lea	s_nothing,a0
	tst.w	b_loading
	beq.s	.printload
	lea	s_debug_load,a0
.printload	moveq	#-1,d6
	bsr	textprint

	; "PLAY"
	lea	s_nothing,a0
	tst.w	b_buffering_lock
	bne.s	.printplay
	lea	s_debug_play,a0
.printplay	moveq	#-1,d6
	bsr	textprint

	; load ptr
	lea	s_hex,a6
	move.l	a6,a0
	move.l	load_ptr,d0
	bsr	itoahex
	move.l	a6,a0
	addq.l	#2,a0
	moveq	#7,d6
	bsr	textprint

	; play ptr
	lea	s_hex,a6
	move.l	a6,a0
	move.l	play_ptr,d0
	bsr	itoahex
	move.l	a6,a0
	addq.l	#2,a0
	moveq	#7,d6
	bsr	textprint

	; last rendered frame
	lea	s_hex,a6
	move.l	a6,a0
	move.w	play_frm,d0
	bsr	itoahex
	move.l	a6,a0
	addq.l	#4,a0
	moveq	#3,d6
	bsr	textprint

	; next palette frame
	lea	s_hex,a6
	move.l	pal_ptr,a0
	move.w	(a0),d0
	move.l	a6,a0
	bsr	itoahex
	move.l	a6,a0
	addq.l	#4,a0
	moveq	#3,d6
	bsr	textprint

	bra	.nodebug
	

* Timer A
* used only for debugging to check when the audio DMA buffer loops
timer_a	move.b	#1,$fffffa1f.w
	;tst.w	debug_color
	;bne.s	.debug_ta
	rte

.debug_ta	COLOR_DEBUG $700
	REPT 128
	nop
	ENDR
	COLOR_DEBUG $000
dummy_rte	rte

* RENDER is triggered by HBL
* because this way it can be interrupted by VBL (frame counter/debug info) and MFP (Timer A/B)
* it's triggered by a Timer B event at the last visible line to swap buffers ASAP
* if a render is already in progress HBL is not enabled for this frame

	; monochrome mode needs Timer B two times because the render takes place at line 390
tb_mono	sf	$fffffa1b.w
	move.l	#tb_render,$120.w
	move.b	#190,$fffffa21.w	; 10 lines earlier: Timer B may be fired too late because of blitter transfers
	move.b	#8,$fffffa1b.w
	rte

tb_render	tst.w	b_lock_render
	bne.s	.locked		; don't enable HBL if a render is already in progress
	and.w	#$f0ff,(sp)
	or.w	#$0100,(sp)	; enable HBL after rte
.locked	rte

b_lock_render
	dc.w	0

hbl	;move.w	$ffff8240.w,-(sp)
	; green
	COLOR_DEBUG $070

	tst.w	b_lock_render
	bne	endhbl		; render already in progress (actually should not happen)
	move.w	#-1,b_lock_render

	movem.l	d0-a6,-(sp)

	tst.w	b_buffering_lock
	bne	norender

	move.w	vbl_count,d0
	cmp.w	next_refresh,d0
	blt	norender
	addq.w	#vbl_per_frame,d0
	move.w	d0,next_refresh

render	move.l	idx_play,a1	; current frame
	move.l	(a1),a1		; pcm start
	ble	enter_buffering	; null ptr = not loaded yet

	add.w	#1,rendered_frame 	; for debug purpose only

	; set the new DMA audio buffer
	; will be used when DMA loops automatically
	; note that it would be ideally in 1 (mono) or 2 (color) vbls and then be in sync with the video
	; there is many ways to achieve that but in this version it relies on the first audio frame
	; to be smaller so the DMA loop happens just before this 'render' function is called
	move.l	a1,play_ptr
	add.w	#1,play_frm
	move.l	(a1)+,d2		; pcm length
	move.l	a1,d0
	add.l	d2,a1		; pcm end
	move.l	a1,d1
	AUDIO_DMA_SET d0,d1

	; hack to avoid emulation audio cracks
	movep.l	$07(a6),d0
	and.l	#$00ffffff,d0
	move.l	d0,aplay_ptr
	add.w	#1,aplay_frm


	; check if unchanged frame
	; apply to frame N-2 so we need to save this
	tst.w	swap_buffers
	beq	.noswap

	; swap video buffers
	; so next vbl we're gonna see the frame rendered 2 vbls ago
	move.l	screen_render_ptr,a0
	move.l	screen_display_ptr,screen_render_ptr
	move.l	a0,screen_display_ptr
	sub.w	#line_length*8,a0
	move.l	a0,screen_debug_ptr

	bsr	set_screen

	; empty graphics, skip render
.noswap	move.w	(a1),swap_buffers
	beq	.noblitter
	
	; software part (generated code in file)
	move.l	screen_render_ptr,a6
	jsr	2(a1)

	; purple
	COLOR_DEBUG $303

	move.w	(a1)+,d0
	add.w	d0,a1	; size of software render code


	move.w	(a1)+,d0	; nb of blitter blocks
	blt	.noblitter

	;move.w	#$707,$ffff8240.w
	
	IFNE	blitter
	move.w	#2,$ffff8a20.w	; src x byte increment
	move.w	#2,$ffff8a22.w	; src y byte increment
	move.w	#-1,$ffff8a28.w	; endmask1
	move.w	#-1,$ffff8a2a.w	; endmask2
	move.w	#-1,$ffff8a2c.w	; endmask3
	move.w	#2,$ffff8a2e.w	; dest x byte increment
	ENDC
	move.w	(a1)+,d3		; blocks # bitplanes (1/2/4)
	move.w	d3,d4
	IFNE	blitter
	add.w	d3,d3
	subq.w	#2,d3
	move.w	#line_length,d2
	sub.w	d3,d2
	move.w	d2,$ffff8a30.w	; dest y byte increment
	clr.b	$ffff8a3d.w	; clear skew register
	ENDC


.nextblit	move.l	screen_render_ptr,a6
	add.w	(a1)+,a6		; offset from start of screen
	move.w	(a1)+,d1
	bmi	video_end		; (assert) y count negative => bug!

	IFNE	blitter
	move.w	d1,$ffff8a38.w	; y count
	move.w	d4,$ffff8a36.w	; x word count
	move.w	#2,$ffff8a20.w	; src x byte increment
	move.w	#2,$ffff8a22.w	; src y byte increment
	move.w	(a1)+,d1
	move.w	d1,$ffff8a3a.w	; HOP+OP
	cmp.w	#$0203,d1		; copy mode ?
	beq.s	.copymode
	clr.w	$ffff8a20.w	; *no* src x byte increment
	clr.w	$ffff8a22.w	; *no* src y byte increment
.copymode	move.l	a1,$ffff8a24.w	; source
	move.l	a6,$ffff8a32.w	; destination
	move.b	#%11000000,$ffff8a3c.w	; start HOG
	nop			; wait a few cycles for the blitter to start (STE/MSTE)
	nop
	move.l	$ffff8a24.w,a1

	ELSE
	move.w	(a1)+,d3	; HOP+OP $0203 copy / $0100 0's fill / $010F 1's fill
	* WARNING crude software emulation / very slow unless there is a CPU cache
	* only for debug purpose or TT compatibility
	cmp.w	#$0203,d3
	beq	.softcopy
	moveq	#0,d5
	cmp.w	#$0100,d3
	beq.s	.softfill
	moveq	#-1,d5

.softfill	cmp.w	#4,d4
	blt.s	.softf2bpp
	move.w	d1,d2
	subq.w	#1,d2
.softfill4	move.l	d5,(a6)+
	move.l	d5,(a6)
	lea	line_length-4(a6),a6
	dbra.s	d2,.softfill4
	bra.s	.endsoftcopy

.softf2bpp	cmp.w	#2,d4
	blt.s	.softf1bpp
	move.w	d1,d2
	subq.w	#1,d2
.softfill2	move.l	d5,(a6)
	lea	line_length(a6),a6
	dbra.s	d2,.softfill2
	bra.s	.endsoftcopy

.softf1bpp	move.w	d1,d2
	subq.w	#1,d2
.softfill1	move.w	d5,(a6)
	lea	line_length(a6),a6
	dbra.s	d2,.softfill1
	bra.s	.endsoftcopy

.softcopy	cmp.w	#4,d4
	blt.s	.soft2bpp
	move.w	d1,d2
	subq.w	#1,d2
.softcopy4	move.l	(a1)+,(a6)+
	move.l	(a1)+,(a6)
	lea	line_length-4(a6),a6
	dbra.s	d2,.softcopy4
	bra.s	.endsoftcopy

.soft2bpp	cmp.w	#2,d4
	blt.s	.soft1bpp
	move.w	d1,d2
	subq.w	#1,d2
.softcopy2	move.l	(a1)+,(a6)
	lea	line_length(a6),a6
	dbra.s	d2,.softcopy2
	bra.s	.endsoftcopy

.soft1bpp	move.w	d1,d2
	subq.w	#1,d2
.softcopy1	move.w	(a1)+,(a6)
	lea	line_length(a6),a6
	dbra.s	d2,.softcopy1

.endsoftcopy
	ENDC

	IFNE	monochrome
	tst.w	debug_color
	beq.s	.nodebug
	not.w	$ffff8240.w
.nodebug
	ENDC

	dbra.s	d0,.nextblit

.noblitter
	IFNE	loop_play	
	; clear the idx playlist in case the video loops and inc idx_play+4
	move.l	idx_play,a0
	move.l	a0,a1
	addq	#4,a0
	cmp.l	#-1,(a0)
	bne	.noloop1

	; reset all ptr/counters
	move.l	#play_index,a0
	move.w	#loop_frame,play_frm
	move.w	#loop_frame,aplay_frm
	move.l	#palettes+(34*5),pal_ptr

.noloop1	move.l	a0,idx_play
	clr.l	(a1)
	ELSE
	add.l	#4,idx_play
	ENDC
	bra.s	endrender

enter_buffering
	move.b	#%00,$ffff8901.w	; stop sound
	move.w	#-1,b_buffering_lock

endrender	
	movem.l	(sp)+,d0-a6
	
	clr.w	b_lock_render
endhbl	;move.w	(sp)+,$ffff8240.w
	and.w	#$f0ff,(sp)
	or.w	#$0300,(sp)	; disable HBL after rte (should not work on 68030+)
	rte

norender	bsr	set_screen
	bra.s	endrender

set_screen	tst.w	debug_info
	beq.s	.noshift
	move.b	screen_debug_ptr+1,$ffff8201.w
	move.b	screen_debug_ptr+2,$ffff8203.w
	move.b	screen_debug_ptr+3,$ffff820d.w
	bra.s	.end
.noshift	move.b	screen_display_ptr+1,$ffff8201.w
	move.b	screen_display_ptr+2,$ffff8203.w
	move.b	screen_display_ptr+3,$ffff820d.w
.end	rts

*** MISC

ikbd	lea	$fffffc00.w,a1
.l1	move.b	(a1),d1
	btst	#1,d1
	beq.s	.l1
	move.b	d0,2(a1)
	rts

flush	move.w	d0,-(sp)
.l1	btst.b	#0,$fffffc00.w
	beq.s	.s1
	move.b	$fffffc02.w,d0
	bra.s	.l1
.s1	move.w	(sp)+,d0
	rts

error_needscolor
	pea	s_errcoloronly
	bra.s	error_message
file_error pea	s_errfile
	bra.s	error_message
buyram	pea	s_errmemory
error_message
	move.w	#9,-(sp)
	trap	#1
	addq	#6,sp

	move.w	#8,-(sp)
	trap	#1
	addq	#2,sp

	jmp	end


*** STRING FUNCTIONS

	; a0 text to print
	; a1 destination address on screen
	; d6 max text length - 1

textprint_end
	rts

textprint	lea	smallfont(pc),a2
	lea	SmallTab(pc),a5
	;moveq	#3,d1		; nb bitplanes
.startline	move.l	a1,a6

.loop	moveq	#0,d2
	move.b	(a0)+,d2	; char
	beq	textprint_end
	cmp.b	#13,d2	; CR
	bne.s	.nocr
	
	; CR
	move.l	a6,a1
	add.w	#line_length*9,a1
	bra.s	.startline

.nocr	sub.b	#32,d2	; ASCII-32
	move.b	(a5,d2.w),d2	; offset to char
	lsl.w	#3,d2	; size of char = 8 bytes
	lea	(a2,d2.w),a3	; source

.print
	;REPT	4
	move.b	(a3)+,(a1)
	move.b	(a3)+,line_length(a1)
	move.b	(a3)+,line_length*2(a1)
	move.b	(a3)+,line_length*3(a1)
	move.b	(a3)+,line_length*4(a1)
	move.b	(a3)+,line_length*5(a1)
	move.b	(a3)+,line_length*6(a1)
	move.b	(a3),line_length*7(a1)
	addq	#8,a1
	;subq	#7,a3
	;ENDR
	;dbra.s	d1,.print	

	IFEQ	monochrome
	move.l	a1,d5
	btst.w	#0,d5
	bne.s	.odd
	ENDC
	subq	#7,a1
	dbra	d6,.loop
	rts
.odd	subq	#1,a1
	dbra	d6,.loop
	rts
	

	; d0 value to convert
	; a0 textbuffer (8 bytes)
itoahex	lea	hexstr,a2
	lea	8(a0),a0
	moveq	#7,d3
	move.w	#$F,d2
.loop	move.w	d0,d1
	and.w	d2,d1
	move.b	(a2,d1.w),-(a0)
	lsr.l	#4,d0
	dbra.s	d3,.loop
	rts


hexstr	dc.b	'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'
	even

convert_palette_ste
	move.w	#15,d7
.stepal	move.w	(a0),d0
	move.w	d0,d1
	and.w	#$111,d0
	lsl.w	#3,d0
	and.w	#$eee,d1
	lsr.w	#1,d1
	or.w	d1,d0
	move.w	d0,(a0)+
	dbra	d7,.stepal
	rts

	section	data

	even

vbl_count	dc.w	0
next_refresh
	dc.w	0
b_loading	dc.w	0
b_buffering_lock
	dc.w	-1
b_first_load
	dc.w	-1
b_fileerror
	dc.w	0
screen_render_ptr
	dc.l	bufscreen+line_length*8
screen_display_ptr 
	dc.l	bufscreen2+line_length*8
screen_debug_ptr
	dc.l	bufscreen2
file_handle
	dc.w	0
debug_color
	dc.w	0
debug_info	dc.w	0



idx_play	dc.l	play_index		; ptr to next frame to play
idx_load	dc.l	vid_index		; ptr to frame size 16bits list
idx_loaded	dc.l	play_index		; ptr to next frame to load
load_ptr	dc.l	0	; start at vid_buffer
play_ptr	dc.l	0	; video frame ptr
	dc.w	0	; 32b align
play_frm	dc.w	0	; video frame number
aplay_ptr	dc.l	0	; audio frame ptr
	dc.w	0	; 32b align
aplay_frm	dc.w	0	; audio frame number
play_offset
	dc.l	0
load_offset
	dc.l	0
size_toload
	dc.l	0
vid_buffer	dc.l	0
vid_buffer_end
	dc.l	0
vid_buffer_end_max
	dc.l	0
rendered_frame
	dc.w	0
swap_buffers
	dc.w	-1


s_vid_filename
	dc.b	"ANKHA.DAT",0
s_idx_filename
	dc.b	"ANKHA.IDX",0
s_debug_load
	dc.b	"LOAD ",0
s_debug_play
	dc.b	"PLAY ",0
s_hex	dc.b	"         ",0
s_nothing	dc.b	"     ",0
s_title	dc.b	"   ANKHA   ",0


s_errcoloronly
	dc.b	"Works in color mode only T_T",10,13,0
s_errmemory
	dc.b	"Not enough memory available T_T",10,13,10,13,"Please buy some RAM and try again.",10,13,0
s_errfile
	dc.b	"File error",10,13,0

smallfont	dc.b	0,0,0,0,0,0,0,0
	incbin	"SMALL"
	dc.b	$ff,$ff,$ff,$ff,$ff,$ff,$ff,0
SmallTab	dc.b	0,38,0,48,0,0,0,42,43,44,0,46,41,45,47,0
	dc.b	1,2,3,4,5,6,7,8,9,10
	dc.b	39,40,0,0,0,37,0
	dc.b	11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27
	dc.b	28,29,30,31,32,33,34,35,36,37,38,39,40,41
	even

pal_ptr	dc.l	palettes

palette	dc.w	$000,$b61,$D81,$C80,$FFE,$520,$225,$128,$ED0,$B90,$976,$23C,$EA6,$87C,$D67,$ECA

palettes	incbin	"ankha.pal"
	dc.w	$fff0

	section	bss

	even
Save_Mfp	ds.l	16
Save_Vec	ds.l	17
old_ints	ds.b	25
	even
old_palette
	ds.w	16
old_screen	ds.l	1
old_rez	ds.b	1
old_hz	ds.b	1
	even
vid_index	ds.w	nb_frames+1
play_index	ds.l	nb_frames+1
buf_nothing
	ds.w	40;
buf_nothing_end
bufscreen	ds.b	32000+line_length*8
bufscreen2	ds.b	32000+line_length*8