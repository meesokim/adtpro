;
; ADTPro - Apple Disk Transfer ProDOS
; Copyright (C) 2007 by David Schmidt
; david__schmidt at users.sourceforge.net
;
; This program is free software; you can redistribute it and/or modify it 
; under the terms of the GNU General Public License as published by the 
; Free Software Foundation; either version 2 of the License, or (at your 
; option) any later version.
;
; This program is distributed in the hope that it will be useful, but 
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License 
; for more details.
;
; You should have received a copy of the GNU General Public License along 
; with this program; if not, write to the Free Software Foundation, Inc., 
; 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
;

ERRNUM:	.byte 0
DRVNUM:	.byte 0
PARM_ADDR_H1:	.byte $D5
PARM_ADDR_H2:	.byte $AA
PARM_ADDR_H3:	.byte $96
NBUF2	= $AA
ZBUFFER	= $44 ; and $45 : 256 bytes buffer addr
RD_ERR	= $42 ; read data field err code
CHECKSUM	= $3A ; sector checksum

;==============================*
;                              *
; INIT DISK II DRIVE FOR READ  *
;                              *
;==============================*

INIT_DISKII:
	LDA   DRVON      ; drive on
	LDX   DRVNUM     ; select drive (1 or 2)
	LDA   DRVSL1-1,X
	LDA   DRVRDM     ; set mode to:
	LDA   DRVRD      ; read

	LDA   DRVSM0OFF  ; set all stepper motor phases to off
	LDA   DRVSM1OFF
	LDA   DRVSM2OFF
	LDA   DRVSM3OFF

	LDY   #4         ; wait for 300 rpm
:	LDA   #0
	JSR   WAIT_SPEED
	DEY
	BNE   :-
	RTS

WAIT_SPEED:
	SEC
SPEED_1:
	PHA
SPEED_2:
	SBC   #1
	BNE   SPEED_2
	PLA
	SBC   #1
	BNE   SPEED_1
	RTS


;==============================*
;                              *
;  PUT READ HEAD ON TRACK $00  *
;                              *
;==============================*

GO_TRACK0:
	LDA   #0         ; init MOVE_ARM values
	STA   CURHTRK
	STA   GOHTRK

	JSR   READ_ADDR_FD ; read current T/S under R/W head
	BCC   TRACK0_1         ; no err -> known track

	                 ; unable to read current track which is unknown
	LDA   #80        ; Force 80 "tracks" recalibration
	STA   RS_TRACK   ; (=40 dos 3.3 tracks)

TRACK0_1:
	LDA   RS_TRACK   ; already on track 0?
	BEQ   TRACK0_3         ; yes

	                 ; go to track 0
	LDA   RS_TRACK   ; from current track
TRACK0_2:
	ASL              ; translate to half track
	STA   CURHTRK
	LDA   #0         ; to track 0
	JSR   MOVE_ARM   ; move r/w head on the target track
	JSR   READ_ADDR_FD ; check if good track
	BCS   TRACK0_3         ; can't read but can't do more.

	LDA   RS_TRACK   ; track 0?
	BNE   TRACK0_2         ; no, retry

TRACK0_3:
	RTS


;==============================*
;                              *
; READ THE FIRST ADDRESS FIELD *
; UNDER THE R/W HEAD AND GET   *
; TRACK AND SECTOR NUMBERS     *
;                              *
;==============================*

; Out: Carry      = 0 -> no err and:
;      RS_VOLUME  Volume found
;      RS_TRACK   Track found (DOS 3.3)
;      RS_PHYSEC  Physical sector found
;      RS_LOGSEC  Logicial sector found
;
;      Carry      = 1 -> err
;      Acc        = err num
;      ERRNUM     = err num
;	          1 = no addr header marker
;	          2 = bad sector

READ_ADDR_FD:
	LDX   #0         ; init low/high max counter (10*256 nibbles)
	LDY   #10
	JMP   ADDR_FD_1         ; start research

ADDR_FD_2:
	INX              ; read nibble isn't a marker. Add 1 to counter
	BNE   ADDR_FD_1         ; and search again
	DEY
	BNE   ADDR_FD_1
	                 ; counter=max. Stop and set error
	LDA   #1         ; error : no addr field headers
	STA   ERRNUM
	SEC
	RTS

ADDR_FD_1:       LDA   DRVRD      ; read nibble
	BPL   ADDR_FD_1
	                 ; Check D5 (1st addr field marker D5 AA 96)
	CMP   PARM_ADDR_H1
	BNE   ADDR_FD_2         ; bad nibble -> next

ADDR_FD_3:
	LDA   DRVRD      ; read nibble
	BPL   ADDR_FD_3
	                 ; Check AA (2nd addr field marker D5 AA 96)
	CMP   PARM_ADDR_H2
	BNE   ADDR_FD_2         ; bad nibble -> next

ADDR_FD_4:
	LDA   DRVRD      ; read nibble
	BPL   ADDR_FD_4
	                 ; Check 96 (3rd addr field marker D5 AA 96)
	CMP   PARM_ADDR_H3
	BNE   ADDR_FD_2         ; bad nibble -> next

; Ok header markers found. Now read addr informations.
; Read 6 nibbles and get 3 bytes (volume/track/sector)

	LDY   #0         ; Y[0,2] * 2 = 6 nibbles (counter)
ADDR_FD_5:
	LDA   DRVRD      ; read 1st nibble
	BPL   ADDR_FD_5

	STA   RS_TEMP    ; save first nibble (format: 1A1B1C1D)

ADDR_FD_6:
	LDA   DRVRD      ; read 2nd nibble
	BPL   ADDR_FD_6
	                 ; acc=1E1F1G1H
	SEC              ; 4-4 decoding
	ROL   RS_TEMP    ; mask AND: RS_TEMP=A1B1C1D1
	AND   RS_TEMP    ; result acc=ABCDEFGH
	STA   RS_INFOS,Y ; save byte

	INY              ; read next 2 nibbles
	CPY   #3
	BNE   ADDR_FD_5

	LDX   RS_PHYSEC  ; check sector
	BMI   ADDR_FD_7         ; >127 -> bad
	CPX   #16
	BPL   ADDR_FD_7         ; >15 -> bad

	LDA   TSECT,X    ; skewing to get and
	STA   RS_LOGSEC  ; save logical sector number
	CLC              ; no err
	RTS

ADDR_FD_7:
	LDA   #2         ; error : bad sector
	STA   ERRNUM
	SEC
	RTS


RS_TEMP:
	.BYTE 0          ; building byte (work aera)
RS_INFOS:                  ; Sector informations (read)
RS_VOLUME:
	.BYTE  0          ; volume number
RS_TRACK:
	.BYTE 0          ; track number
RS_PHYSEC:
	.BYTE  0          ; physical sector number
RS_LOGSEC:
	.BYTE  0          ; sector number
	                 ; skewing
TSECT:	.byte $0, $8, $1, $9, $2, $a, $3, $b, $4, $c, $5, $d, $6, $e, $7, $f
;             0l  0h  1l  1h  2l  2h  3l  3h  4l  4h  5l  5h  6l  6h  7l  7h

;==============================*
;                              *
; MOVE ARM TO A "WANTED" TRACK *
;                              *
;==============================*

; In : CURHTRK  "from" current half track [0,68]
;      Acc     "to"   dos 3.3 track [0,34]
;
; Assume slot 6 (no slot indexation)
;
; E.g 1: from T$22 (half=$44) to T$20 (half=$40)  >> DESC <<
;        GOHTRK :$40
;        CURHTRK:$44    CURHTRK > GOHTRK ==> do -1
;                    low 2 bits * 2 + softswitch -> phase on/off
;        CURHTRK:$44-1=$43 -> 3*2 +$C0E1 = $C0E7 -> phase 3 on
;        SAVHTRK:$44       -> 0*2 +$C0E0 = $C0E0 -> phase 0 off
;        CURHTRK:$43-1=$42 -> 2*2 +$C0E1 = $C0E5 -> phase 2 on
;        SAVHTRK:$43       -> 3*2 +$C0E0 = $C0E6 -> phase 3 off
;        CURHTRK:$42-1=$41 -> 1*2 +$C0E1 = $C0E3 -> phase 1 on
;        SAVHTRK:$42       -> 2*2 +$C0E0 = $C0E4 -> phase 2 off
;        CURHTRK:$41-1=$40 -> 0*2 +$C0E1 = $C0E1 -> phase 0 on
;        SAVHTRK:$41       -> 1*2 +$C0E0 = $C0E2 -> phase 1 off
;        CURHTRK:$40 = GOHTRK ==> END
;
; E.g 2: from T$10 (half=$20) to T$11 (half=$22)  >> ASC <<
;        GOHTRK :$22
;        CURHTRK:$20    CURHTRK < GOHTRK ==> do +1
;                    low 2 bits * 2 + softswitch -> phase on/off
;        CURHTRK:$20+1=$21 -> 1*2 +$C0E1 = $C0E3 -> phase 1 on
;        SAVHTRK:$20       -> 0*2 +$C0E0 = $C0E0 -> phase 0 off
;        CURHTRK:$21+1=$22 -> 2*2 +$C0E1 = $C0E5 -> phase 2 on
;        SAVHTRK:$21       -> 1*2 +$C0E0 = $C0E2 -> phase 1 off
;        CURHTRK:$22 = GOHTRK ==> END

MOVE_ARM:
	ASL              ; *2 (dos 3.3 track -> half track)
	STA   GOHTRK     ; wanted half track

ARM_1:	LDA   CURHTRK    ; start from current half track
	STA   SAVHTRK    ; save current half track

	SEC              ; current half track - wanted half track
	SBC   GOHTRK
	BEQ   ARM_OK     ; we're on it -> end

	BCS   ARM_2         ; CURHTRK > GOHTRK

	                 ; track ASC, phase ASC
	INC   CURHTRK    ; position to next half track
	BCC   ARM_3
	                 ; track DESC, phase DESC
ARM_2:	DEC   CURHTRK    ; position to previous half track

ARM_3:	JSR   SEEK1      ; first phase (=current half track +/- 1)
	JSR   WAIT_ARM   ; delay
	LDA   SAVHTRK    ; saved track : 2nd phase (=current track)
	AND   #%00000011 ; reduce half track to phase 0 or 1 or 2 or 3
	ASL              ; *2: now 0 or 2 or 4 or 6. Ready for softswitch
	TAX
	LDA   DRVSM0OFF,X ; phase off
	                 ; $C0E0 or $C0E2 or $C0E4 or $C0E6
	JSR   WAIT_ARM   ; delay
	BEQ   ARM_1         ; always

SEEK1:	LDA   CURHTRK    ; use next/previous half track
	AND   #%00000011 ; reduce half track to phase 0 or 1 or 2 or 3
	ASL              ; *2: now 0 or 2 or 4 or 6
	TAX              ; use it as index
	LDA   DRVSM0ON,X ; for phase on: 1 or 3 or 5 or 7
	                 ; $C0E1 or $C0E3 or $C0E5 or $C0E7
ARM_OK:	RTS

WAIT_ARM:
	LDA   #$28       ; delay (stepper motor)
	SEC
ARM_1_2:
	PHA
ARM_2_2:
	SBC   #1         ; first loop
	BNE   ARM_2_2

	PLA
	SBC   #1         ; second loop
	BNE   ARM_1_2

	RTS              ; acc=0

CURHTRK:
	.BYTE 0          ; from current half track
SAVHTRK:
	.BYTE 0          ;  saved current half track
GOHTRK:	.BYTE 0          ; to "wanted" half track


;==============================*
;                              *
;         LOAD 5 TRACKS        *
;                              *
;==============================*

; In : acc = first track

LOAD_TRACKS:
	sta TRK		; first track
	clc
	adc #$06
	sta TRACKS_3+1	; last track+1
	lda TRK		; Fetch that first track agian

; Move arm

	CMP   #0         ; track 0?
	BEQ   TRACKS_2         ; arm already on it

TRACKS_5:
	LDA   GOHTRK     ; from current half track
	STA   CURHTRK
	LDA   TRK        ; to dos 3.3 track
	JSR   MOVE_ARM   ; move r/w head on the target track

; Calculate HI address where loaded sectors are stored

TRACKS_2:
	LDX   TRK
	LDY   #$0F       ; init sector #

TRACKS_1:
	TYA              ; sector # in Y reg
	CLC
	ADC   ADR_TRK,X  ; add first HI addr
	STA   SKT_BUF,Y  ; load to this HI addr
	STA   SKT_BUF2,Y ; idem
	DEY
	BPL   TRACKS_1

	LDA   RWCHR       ; print R on track read status
	jsr COUT1

	LDA   RWCHROK       ; default=no err
	STA   ERR_READ_TRK

	JSR   LOAD_TRACK ; load 1 track

	LDA   ERR_READ_TRK
	ORA   #%10000000
	CMP   RWCHROK
	BEQ   TRACKS_4

	PHA              ; save track status
	INC   ERR_READ   ; a read error occurs
	JSR   FILLZ      ; fill bad sectors with 0
	PLA              ; restore track status

TRACKS_4:
	LDX   TRK        ; print final track read status
	jsr COUT1
	INX              ; next track
	STX   TRK
TRACKS_3:
	CPX   #$FF       ; last track?
	BNE   TRACKS_5

	RTS

TRK:	.BYTE 0          ; current track
SKT_BUF:
	.RES  16         ; HI addr of the 16 sectors (working)
SKT_BUF2:
	.RES  16         ; idem (don't change)
ADR_TRK:
	.BYTE $44,$54,$64,$74,$84
ERR_READ:              ; read error flag
	.BYTE 0


;==============================*
;                              *
;        LOAD A TRACK          *
;                              *
;==============================*

; Out: ERR_READ_TRK   "." = no err
;                     "*" = err
;      SKT_RCOUNT DS 16    "." sector ok
;                          '*' bad sector

LOAD_TRACK:
	LDY   #15        ; init counter for each sector
	LDA   #'0'
TRACK_LOAD_1:
	STA   SKT_RCOUNT,Y
	DEY
	BPL   TRACK_LOAD_1

	LDA   #16
	STA   CNT_BAD    ; init bad sector number counter (read addr field)
	STA   CNT_OK     ; init correct sector count (read data field)

	LDA   #32        ; 16 sectors * 2
	STA   CNT_RAF    ; init read counter of already done sectors
	                 ; before stop track process

TRACK_LOAD_15:
	DEC   CNT_RAF
	BNE   TRACK_LOAD_3

	JMP   TRACK_LOAD_14        ; remaining sectors are bad (can't find addr field)

TRACK_LOAD_3:
	JSR   READ_ADDR_FD ; read current T/S under R/W head
	BCC   TRACK_LOAD_19        ; no err

	JMP   TRACK_LOAD_2         ; err

TRACK_LOAD_19:
	LDX   RS_LOGSEC  ; logical sector
	LDY   SKT_BUF,X  ; HI addr
	BEQ   TRACK_LOAD_15        ; already read, try another one

	LDA   #32        ; 16 sectors * 2
	STA   CNT_RAF    ; init read counter of already done sectors
	                 ; before stop track process

	JSR   READ_SEC_DATA  ; read sector
	BCS   TRACK_LOAD_5         ; error

	LDX   RS_LOGSEC
	LDA   SKT_RCOUNT,X ; first read?
	CMP   #'0'
	BEQ   TRACK_LOAD_21        ; yes
	                 ; keep current read number
	.BYTE $2C        ; false BIT
TRACK_LOAD_21:
	LDA   RWCHR       ; ok

TRACK_LOAD_13:
	STA   TRACK_LOAD_12+1      ; sector status for display ONLY
	LDA   #0         ; set sector=ok read
	STA   SKT_BUF,X
	LDA   RWCHR      ; sector status
	STA   SKT_RCOUNT,X
;	LDA   STAT_LOW,X ; Low screen addr
;	STA   TRACK_LOAD_6+1
;	LDA   STAT_HIGH,X ; High screen addr
;	STA   TRACK_LOAD_6+2
	LDY   TRK
TRACK_LOAD_12:
	LDA   RWCHR       ; Write status on screen
TRACK_LOAD_6:
;	STA   $FFFF,Y

TRACK_LOAD_9:
	DEC   CNT_OK     ; -1 sector to do
	BNE   TRACK_LOAD_3         ; not finished
	RTS              ; keep default ERR_READ_TRK

; Error while reading data field

TRACK_LOAD_5:
	TAY              ; save err num

	LDX   RS_LOGSEC
	INC   SKT_RCOUNT,X ; +1 time
	LDA   SKT_RCOUNT,X
	CMP   #':'
	BNE   TRACK_LOAD_7

	CPY   #5         ; checksum?
	BNE   TRACK_LOAD_11        ; no

TRACK_LOAD_11:
	LDA   CHR_X
	STA   SKT_RCOUNT,X
	STA   ERR_READ_TRK

TRACK_LOAD_7:
;	LDA   STAT_LOW,X ; Low screen addr
;	STA   TRACK_LOAD_8+1
;	LDA   STAT_HIGH,X ; High screen addr
;	STA   TRACK_LOAD_8+2
;	LDY   TRK
;	LDA   SKT_RCOUNT,X ; Write sector status on screen
TRACK_LOAD_8:
;	STA   $FFFF,Y
;	CMP   #'*'
;	BEQ   TRACK_LOAD_20

	JMP   TRACK_LOAD_3

TRACK_LOAD_20:
;	LDA   #0         ; set sector=ok read
;	STA   SKT_BUF,X
;	BEQ   TRACK_LOAD_9

; Error while reading addr field

TRACK_LOAD_2:
	CMP   #1         ; no markers
	BEQ   TRACK_LOAD_4

	                 ; bad sector number
	DEC   CNT_BAD
	BEQ   TRACK_LOAD_4         ; full track is bad

	JMP   TRACK_LOAD_3         ; not yet 16 errors

; Bad Track

TRACK_LOAD_4:
;	LDA   #$01       ; INV 'A'
;	LDX   TRK
;TODO         JSR   PRINT_T_STAT ; can't read track

	LDY   #15        ; init counter for each sector
	LDA   #'*'       ; sector status=error
TRACK_LOAD_10:
	STA   SKT_RCOUNT,Y
	DEY
	BPL   TRACK_LOAD_10

	LDA   #'*'       ; bad track
	STA   ERR_READ_TRK
	RTS

; Remaining sectors are bad (can't find their addr field)

TRACK_LOAD_14:
	LDX   #15
	LDA   #'*'       ; sector status=error

TRACK_LOAD_17:
;	LDY   SKT_BUF,X  ; sector ok
;	BEQ   TRACK_LOAD_16

;	STA   SKT_RCOUNT,X ; bad sector
;	LDY   STAT_LOW,X ; Low screen addr
;	STY   TRACK_LOAD_18+1
;	LDY   STAT_HIGH,X ; High screen addr
;	STY   TRACK_LOAD_18+2
;	LDY   TRK
TRACK_LOAD_18:
;	STA   $FFFF,Y    ; write err on screen

TRACK_LOAD_16:
;	DEX
;	BPL   TRACK_LOAD_17

;	LDA   #'*'       ; bad track
;	STA   ERR_READ_TRK
	RTS


ERR_READ_TRK:          ; read error flag for an entire track
	.BYTE 0

SKT_RCOUNT:
	.RES 16       ; sector $00 to $0F
CNT_BAD:
	.BYTE 0          ; [0=end,16]
CNT_OK:	.BYTE 0          ; [0=end,16]
CNT_RAF:
	.BYTE 0          ; counter: nbr of read for address field before err


;==============================*
;                              *
; SAVE/RESTORE PAGE0 FOR NBUF2 *
;                              *
;==============================*

; Save

SAV_NBUF2:
	LDX  #$AA
:	LDA   NBUF2-$AA,X
	STA   SAV_P0_NBUF2-$AA,X
	INX
	BNE   :-
	RTS

; Restore

RST_NBUF2:
	LDX  #$AA
:	LDA   SAV_P0_NBUF2-$AA,X
	STA   NBUF2-$AA,X
	INX
	BNE   :-
	RTS

SAV_P0_NBUF2:
	.RES 86      ; save page 0 (before denibblizing)


;==============================*
;                              *
; FILL BAD SECTORS WITH ZEROS  *
;                              *
;==============================*

FILLZ:
	LDA   $EC        ; save used addr page 0
	STA   FILLZ_SV
	LDA   $ED
	STA   FILLZ_SV+1

FILLZ2:
	LDX   #$0F       ; begin with sector $0F
FILLZ_2:
	LDA   SKT_RCOUNT,X ; sector status
	CMP   #'*'       ; err?
	BNE   FILLZ_1         ; no, skip this sector

	                 ; prepare pointer for write
	LDA   SKT_BUF2,X ; HI
	STA   $ED
	LDA   #0         ; LO
	STA   $EC
	                 ; acc=0
	TAY              ; Y=0
FILLZ_3:
	STA   ($EC),Y    ; fill with 0
	INY
	BNE   FILLZ_3

FILLZ_1:
	DEX              ; previous sector
	BPL   FILLZ_2         ; not finished

	RTS

FILLZ_SV:
	.BYTE 0,0        ; page 0 backup


;*******************************
;                              *
; READ DATA FIELD OF A SECTOR  *
; AND POSTNIBBLIZE ON THE FLY  *
;                              *
;*******************************

; In : Y          = high buffer 256 bytes
;
; Out: carry     = 0 -> ok, datas loaded
;
;      carry     = 1 -> err
;      acc       = err code
;          04 : no D5 AA AD headers after reading $20 nibbles
;          05 : bad checksum
;          06 : next nibble after checksum isn't trailer DE
;
; NOTES BEFORE CALLING THIS SUB-ROUTINE:
;  - CHECK ADDR FIELD HEADERS
;  - FILL DATA FIELD HEADERS + FIRST TRAILER (MARKER_* ENT)
;    WITH PROPER USER PARMS
;  - UPDATE MA_STA CODE PART CORRECTLY (MAIN/AUX MEMORY)
;
;*******************************
;
; Content of a data field:
; =======================
;
; D5 AA AD data field header markers
;                                  Nibble index
; 86/$56 nibbles (6&2 complement)  $0000-$0055 (000-085)
; 86/$56 nibbles (bottom third)    $0056-$00AB (086-171)
; 86/$56 nibbles (middle third)    $00AC-$0101 (172-257)
; 84/$54 nibbles (top third)       $0102-$0155 (258-341)
; xx checksum
; DE AA EB data field trailer markers
;
; The 256 bytes buffer in memory where datas are loaded
; (ZBUFFER) is cut in 3 parts:
;
;   ZBUFFER                    Written   Y    e.g. buffer
;   offset                     with           = $1000
; +-------------------------+--------+-----+-------------------+
; ! $00                     !        ! $AA ! first Y=$AB       !
; ! ... bottom third buffer ! STORE1 ! ... ! STA $0F55,Y       !
; ! $55                     !        ! $FF ! last: PLA+STA,$55 !
; +-------------------------+--------+-----+-------------------+
; ! $56                     !        ! $AA !                   !
; ! ... middle third buffer ! STORE2 ! ... ! STA $0FAC,Y       !
; ! $AB                     !        ! $FF !                   !
; +-------------------------+--------+-----+-------------------+
; ! $AC                     !        ! $AC !                   !
; ! ... top third buffer    ! STORE3 ! ... ! STA $1000,Y       !
; ! $FF                     !        ! $FF !                   !
; +-------------------------+--------+-----+-------------------+
;
; There are 4 loops in the program:
; - 1 loop to read the 6&2 complement bits in the
;   auxiliary buffer NBUF2 (86 nibbles)
; - 1 loop to read 86 nibbles, build the final bytes with NBUF2
;   and store them in the bottom third buffer.
; - 1 loop to read 86 nibbles, build the final bytes with NBUF2
;   and store them in the middle third buffer.
; - 1 loop to read 84 nibbles, build the final bytes with NBUF2
;   and store them in the top third buffer.
;
; About the last 3 loops:
; Each loop uses the Y register to store each byte:
;   STORE1  STA bottom third buffer-$AB,Y [$AB,$FF]
;   STORE2  STA middle third buffer-$AA,Y [$AA,$FF]
;   STORE3  STA top third buffer-$AC,Y    [$AC,$FF]
; With the following equivalence:
;   Bottom third buffer = ZBUFFER
;   Middle third buffer = ZBUFFER+$56
;   Top third Buffer    = ZBUFFER+$AC
; The STA addresses are as follow:
;   STORE1 -> STA ZBUFFER-$AB,Y
;   STORE2 -> STA ZBUFFER+$56-$AA,Y = ZBUFFER-$54,Y
;   STORE3 -> STA ZBUFFER,Y
;
; A big part of this sub-routine comes from Apple ProDOS.
; I've done only small changes:
; - The 6&2 complementary buffer is located in page 0.
; - Added a more accurate returned error value if one occurs.
; - Write decoded datas in a selected aux memory bank.

;-------------------------------

;        DS    \          ; start at the beginning of a new page

READ_SEC_DATA:
	                 ; Get data buffer pointers
	STY   STORE3+2   ; +4c. Provides access to top 3rd of buffer
	DEY              ; +2c.
	STY   STORE2+2   ; +4c. Provides access to middle 3rd of buffer
	STY   STORE1+2   ; +4c. Provides access to bottom 3rd of buffer

;-------------------------------
; Data field identification
;-------------------------------

	LDY   #$20       ; +2c. Initialize must find count at $20
	                 ; search data headers
SEARCH_DH:
	DEY              ; +2c. Decrement count - more to do?
	BEQ   EXIT_ERR   ; (+2c). No, then exit

RDNIBLOOP1:
	LDA $C0EC        ; +4c. Read a nibble
	BPL   RDNIBLOOP1

MARKER_DH1:
	EOR   #$D5       ; +2c. Is it 1st header mark?
	BNE   SEARCH_DH  ; (+2c). No, try again

	LDA   #5         ; +2c. Init err # (checksum err)
	STA   RD_ERR     ; +3c.

RDNIBLOOP2:
	LDA $C0EC      ; +4c. Read a nibble
	BPL   RDNIBLOOP2

MARKER_DH2:
	CMP   #$AA       ; +2c. Is it 2nd header mark?
	BNE   MARKER_DH1 ; (+2c). No, see if it is 1st header mark

	LDY   STORE3+2   ; +4c.
	STY   ZBUFFER+1  ; +3c. high
	LDA   #0         ; +2c.
	STA   ZBUFFER    ; +3c. low

RDNIBLOOP3:
	LDA $C0EC      ; +4. Read a nibble
	BPL   RDNIBLOOP3

MARKER_DH3:
	CMP   #$AD       ; +2c. Is it 3rd header mark?
	BNE   MARKER_DH1 ; (+2c). No, see if it is 1st header mark

;-------------------------------
; A running checksum is initialized
;-------------------------------

	LDY   #$AA       ; +2c. Y [$AA,$FF] = $56 nibbles to read
	LDA   #0         ; +2c. Init checksum
READ1:	STA   CHECKSUM   ; +3c.

;-------------------------------
; 86 disk words (6&2 complement nibbles) are read,
; decoded to XXXXXX00 format and stored in the
; auxiliary buffer
;-------------------------------

RDNIBLOOP4:
	LDX $C0EC      ; +4c. Read a nibble [$96-$FF]
	BPL   RDNIBLOOP4

	LDA   NIB_2_6BB-$96,X ; +4c. Translate to 6-bits byte XXXXXX00
	                 ; $96 is the first valid nibble value
	                 ; Y [$AA,$FF]
	STA   NBUF2-$AA,Y ; +5c. And store it.
	EOR   CHECKSUM   ; +3c. Compute running checksum
	INY              ; +2c. Next nibble
	BNE   READ1      ; (+2c). Not finished

;-------------------------------
; The bottom third, middle third, and top third of the
; 256-byte buffer are read from disk and decoded to XXXXXX00
; format, then ORed with 000000XX data which is postnibblized
; on the fly from the auxiliary buffer XXXXXX00 data.
; The combined XXXXXXXX data which is stored to the 256-byte
; buffer is true 8-bit data, just as it resided in a 256-byte
; buffer before it was stored on disk.
;-------------------------------

; ATTN: reading loops -> less than 30 cycles because of the
;       disk speed variation + speed variation due to disk
;       flutter (read "Understanding the Apple IIe", Jim Sather,
;       Chapt 9, page 9-45).

; Read 86 nibbles (bottom third)

	LDY   #$AA       ; +2c. Y [$AA,$FF] = $56 nibble to read
	BNE   RDNIBLOOP5 ; +2c. Branch always taken

EXIT_ERR:
	LDA   #4         ; +2c. Init err #
	STA   RD_ERR     ; +3c.
	SEC              ; set carry flag indicating error
	BCS   LDA_RD_ERR ; return to caller

	                 ; first loop Y=$AB. Last loop Y=$FF.
STORE1:  STA   $FF55,Y    ; +5c. Store byte in bottom third


RDNIBLOOP5:
	LDX $C0EC      ; +4c. Read a nibble
	BPL   RDNIBLOOP5

	                 ; acc used as running checksum
	EOR   NIB_2_6BB-$96,X ; +4c. Translate nibble to 6-bit byte+checksum
	LDX   NBUF2-$AA,Y ; +4c. Bits from auxiliary buffer
	EOR   BIT_PAIR_TBL,X ; +4c. Merge in
	INY              ; +2c. Next nibble
	BNE   STORE1     ; (+2c). Not finished

	PHA              ; +3c. Save last byte for later, no time now
	AND   #$FC       ; +2c. Trip off last two bits XXXXXX00

; Read 86 nibbles (middle third)

	LDY   #$AA       ; +2c. Y [$AA,$FF] = $56 nibbles to read

RDNIBLOOP6:
	LDX $C0EC      ; +4c. Read a nibble
	BPL   RDNIBLOOP6

	EOR   NIB_2_6BB-$96,X ; +4c. Translate nibble to 6-bit byte+checksum
	LDX   NBUF2-$AA,Y ; +4c. Bits from auxiliary buffer
	EOR   BIT_PAIR_TBL+1,X ; +4c. Merge in
STORE2:
	STA   $FFAC,Y    ; +5c. Store byte in middle third
	INY              ; +2c. Next nibble
	BNE   RDNIBLOOP6 ; (+2c). Not finished

; Read 84 nibbles (top third)
	                 ; Y=0
RDNIBLOOP7:
	LDX $C0EC      ; +4c. Read 1st nibble
	BPL   RDNIBLOOP7

	AND   #$FC       ; +2c. Strip off last two bits XXXXXX00

	LDY   #$AC       ; +2c. Y [$AC,$FF] = $54 nibbles to read
DECODE:
	EOR   NIB_2_6BB-$96,X ; +4c. Translate nibble to 6-bit byte+checksum
	LDX   NBUF2-$AC,Y ; +4c. Bits from auxiliary buffer
	EOR   BIT_PAIR_TBL+2,X ; +4c. Merge in
STORE3:
	STA   $FF00,Y    ; +5c. Store byte in top third

RDNIBLOOP8:
	LDX $C0EC      ; +4c. Read nibble
	BPL   RDNIBLOOP8

	INY              ; +2c. Next nibble
	BNE   DECODE     ; (+2c). Not finished

; Last nibble read = checksum

	AND   #$FC       ; +2c. Strip off last two bits XXXXXX00
	EOR   NIB_2_6BB-$96,X ; +4c. Translate nibble to 6-bit byte+checksum
	BNE   ERROR      ; (+2c). Checksum not valid

; Check 1st trailing mark

RDNIBLOOP9:
	LDA $C0EC      ; +4c. Read nibble
	BPL   RDNIBLOOP9

MARKER_DT1:
	CMP   #$DE       ; +2c. Check 1st trailing mark
	CLC              ; +2c.
	BEQ   OK         ; (+2c). Yes, trailer ok

	INC   RD_ERR     ; +5c. 5+1=6 (trailer err)

ERROR:   SEC              ; +2c. Set carry flag indicating error
OK:      PLA              ; +4c. Set byte we stored away, we have time now
	LDY   #$55       ; +2c. Set proper offset
	STA   (ZBUFFER),Y ; +6c. Store byte
LDA_RD_ERR:
	LDA   RD_ERR     ; +3c. acc=err code
	RTS              ; +6c. Return to caller


;==============================*
;                              *
;    Denibblizing table #1     *
;    Nibble to 6-bits byte     *
;      translation table       *
;         (XXXXXX00)           *
;                              *
;===============================

; Translate a valid nibble to 6-bits byte XXXXXX00.
;
; 1 nibble: value from $96 to $FF (=$6A=106 disk bytes) but
;           only $40=64 disk bytes are valids. They have to
;           respect the rules:
;           - bit 7 (high bit) on
;           - at least 2 adjacent bits set excluding bit 7
;           - not a reserved byte ($AA, $D5)
;           - no more than 2 consecutive zero bits
; 6 bits are required to have $40 values.

;	DS    \          ; start at the beginning of a new page

NIB_2_6BB:

;               Index           <== disk byte
;              %XXXXXX00

	.BYTE %00000000  ; $00 <== $96
	.BYTE %00000100  ; $04 <== $97
	.BYTE 0          ;     <== $98 invalid
	.BYTE 0          ;     <== $99 invalid
	.BYTE %00001000  ; $08 <== $9A
	.BYTE %00001100  ; $0C <== $9B
	.BYTE 0          ;     <== $9C invalid
	.BYTE %00010000  ; $10 <== $9D
	.BYTE %00010100  ; $14 <== $9E
	.BYTE %00011000  ; $18 <== $9F
	.BYTE 0          ;     <== $A0 invalid
	.BYTE 0          ;     <== $A1 invalid
	.BYTE 0          ;     <== $A2 invalid
	.BYTE 0          ;     <== $A3 invalid
	.BYTE 0          ;     <== $A4 invalid
	.BYTE 0          ;     <== $A5 invalid
	.BYTE %00011100  ; $1C <== $A6
	.BYTE %00100000  ; $20 <== $A7
	.BYTE 0          ;     <== $A8 invalid
	.BYTE 0          ;     <== $A9 invalid
	.BYTE 0          ;     <== $AA invalid
	.BYTE %00100100  ; $24 <== $AB
	.BYTE %00101000  ; $28 <== $AC
	.BYTE %00101100  ; $2C <== $AD
	.BYTE %00110000  ; $30 <== $AE
	.BYTE %00110100  ; $34 <== $AF
	.BYTE 0          ;     <== $B0 invalid
	.BYTE 0          ;     <== $B1 invalid
	.BYTE %00111000  ; $38 <== $B2
	.BYTE %00111100  ; $3C <== $B3
	.BYTE %01000000  ; $40 <== $B4
	.BYTE %01000100  ; $44 <== $B5
	.BYTE %01001000  ; $48 <== $B6
	.BYTE %01001100  ; $4C <== $B7
	.BYTE 0          ;     <== $B8 invalid
	.BYTE %01010000  ; $50 <== $B9
	.BYTE %01010100  ; $54 <== $BA
	.BYTE %01011000  ; $58 <== $BB
	.BYTE %01011100  ; $5C <== $BC
	.BYTE %01100000  ; $60 <== $BD
	.BYTE %01100100  ; $64 <== $BE
	.BYTE %01101000  ; $68 <== $BF
	.BYTE 0          ;     <== $C0 invalid
	.BYTE 0          ;     <== $C1 invalid
	.BYTE 0          ;     <== $C2 invalid
	.BYTE 0          ;     <== $C3 invalid
	.BYTE 0          ;     <== $C4 invalid
	.BYTE 0          ;     <== $C5 invalid
	.BYTE 0          ;     <== $C6 invalid
	.BYTE 0          ;     <== $C7 invalid
	.BYTE 0          ;     <== $C8 invalid
	.BYTE 0          ;     <== $C9 invalid
	.BYTE 0          ;     <== $CA invalid
	.BYTE %01101100  ; $6C <== $CB
	.BYTE 0          ;     <== $CC invalid
	.BYTE %01110000  ; $70 <== $CD
	.BYTE %01110100  ; $74 <== $CE
	.BYTE %01111000  ; $78 <== $CF
	.BYTE 0          ;     <== $D0 invalid
	.BYTE 0          ;     <== $D1 invalid
	.BYTE 0          ;     <== $D2 invalid
	.BYTE %01111100  ; $7C <== $D3
	.BYTE 0          ;     <== $D4 invalid
	.BYTE 0          ;     <== $D5 invalid
	.BYTE %10000000  ; $80 <== $D6
	.BYTE %10000100  ; $84 <== $D7
	.BYTE 0          ;     <== $D8 invalid
	.BYTE %10001000  ; $88 <== $D9
	.BYTE %10001100  ; $8C <== $DA
	.BYTE %10010000  ; $90 <== $DB
	.BYTE %10010100  ; $94 <== $DC
	.BYTE %10011000  ; $98 <== $DD
	.BYTE %10011100  ; $9C <== $DE
	.BYTE %10100000  ; $A0 <== $DF
	.BYTE 0          ;     <== $E0 invalid
	.BYTE 0          ;     <== $E1 invalid
	.BYTE 0          ;     <== $E2 invalid
	.BYTE 0          ;     <== $E3 invalid
	.BYTE 0          ;     <== $E4 invalid
	.BYTE %10100100  ; $A4 <== $E5
	.BYTE %10101000  ; $A8 <== $E6
	.BYTE %10101100  ; $AC <== $E7
	.BYTE 0          ;     <== $E8 invalid
	.BYTE %10110000  ; $B0 <== $E9
	.BYTE %10110100  ; $B4 <== $EA
	.BYTE %10111000  ; $B8 <== $EB
	.BYTE %10111100  ; $BC <== $EC
	.BYTE %11000000  ; $C0 <== $ED
	.BYTE %11000100  ; $C4 <== $EE
	.BYTE %11001000  ; $C8 <== $EF
	.BYTE 0          ;     <== $F0 invalid
	.BYTE 0          ;     <== $F1 invalid
	.BYTE %11001100  ; $CC <== $F2
	.BYTE %11010000  ; $D0 <== $F3
	.BYTE %11010100  ; $D4 <== $F4
	.BYTE %11011000  ; $D8 <== $F5
	.BYTE %11011100  ; $DC <== $F6
	.BYTE %11100000  ; $E0 <== $F7
	.BYTE 0          ;     <== $F8 invalid
	.BYTE %11100100  ; $E4 <== $F9
	.BYTE %11101000  ; $E8 <== $FA
	.BYTE %11101100  ; $EC <== $FB
	.BYTE %11110000  ; $F0 <== $FC
	.BYTE %11110100  ; $F4 <== $FD
	.BYTE %11111000  ; $F8 <== $FE
	.BYTE %11111100  ; $FC <== $FF


;==============================*
;                              *
;    Denibblizing table #2     *
; Postnibblize bit mask table  *
;                              *
;==============================*

; This table is filled with 0/1/2/3 values (2 bits).
; Only the 3 first values of each line are used.
;
; Index value: $00 to $3F.
; Format: XXefcdab (XX=unused bits).
; Content of BIT.PAIR tables:
;  BIT.PAIR.LEFT   -> ba
;  BIT.PAIR.MIDDLE -> dc
;  BIT.PAIR.RIGHT  -> fe

;         DS    \          ; start at the beginning of a new page

BIT_PAIR_TBL:

;		LEFT     MIDDLE    RIGHT         VALUE
	.BYTE %00000000,%00000000,%00000000,0 ; XX000000
	.BYTE %00000010,%00000000,%00000000,0 ; XX000001
	.BYTE %00000001,%00000000,%00000000,0 ; XX000010
	.BYTE %00000011,%00000000,%00000000,0 ; XX000011

	.BYTE %00000000,%00000010,%00000000,0 ; XX000100
	.BYTE %00000010,%00000010,%00000000,0 ; XX000101
	.BYTE %00000001,%00000010,%00000000,0 ; XX000110
	.BYTE %00000011,%00000010,%00000000,0 ; XX000111

	.BYTE %00000000,%00000001,%00000000,0 ; XX001000
	.BYTE %00000010,%00000001,%00000000,0 ; XX001001
	.BYTE %00000001,%00000001,%00000000,0 ; XX001010
	.BYTE %00000011,%00000001,%00000000,0 ; XX001011

	.BYTE %00000000,%00000011,%00000000,0 ; XX001100
	.BYTE %00000010,%00000011,%00000000,0 ; XX001101
	.BYTE %00000001,%00000011,%00000000,0 ; XX001110
	.BYTE %00000011,%00000011,%00000000,0 ; XX001111

	.BYTE %00000000,%00000000,%00000010,0 ; XX010000
	.BYTE %00000010,%00000000,%00000010,0 ; XX010001
	.BYTE %00000001,%00000000,%00000010,0 ; XX010010
	.BYTE %00000011,%00000000,%00000010,0 ; XX010011

	.BYTE %00000000,%00000010,%00000010,0 ; XX010100
	.BYTE %00000010,%00000010,%00000010,0 ; XX010101
	.BYTE %00000001,%00000010,%00000010,0 ; XX010110
	.BYTE %00000011,%00000010,%00000010,0 ; XX010111

	.BYTE %00000000,%00000001,%00000010,0 ; XX011000
	.BYTE %00000010,%00000001,%00000010,0 ; XX011001
	.BYTE %00000001,%00000001,%00000010,0 ; XX011010
	.BYTE %00000011,%00000001,%00000010,0 ; XX011011

	.BYTE %00000000,%00000011,%00000010,0 ; XX011100
	.BYTE %00000010,%00000011,%00000010,0 ; XX011101
	.BYTE %00000001,%00000011,%00000010,0 ; XX011110
	.BYTE %00000011,%00000011,%00000010,0 ; XX011111

	.BYTE %00000000,%00000000,%00000001,0 ; XX100000
	.BYTE %00000010,%00000000,%00000001,0 ; XX100001
	.BYTE %00000001,%00000000,%00000001,0 ; XX100010
	.BYTE %00000011,%00000000,%00000001,0 ; XX100011

	.BYTE %00000000,%00000010,%00000001,0 ; XX100100
	.BYTE %00000010,%00000010,%00000001,0 ; XX100101
	.BYTE %00000001,%00000010,%00000001,0 ; XX100110
	.BYTE %00000011,%00000010,%00000001,0 ; XX100111

	.BYTE %00000000,%00000001,%00000001,0 ; XX101000
	.BYTE %00000010,%00000001,%00000001,0 ; XX101001
	.BYTE %00000001,%00000001,%00000001,0 ; XX101010
	.BYTE %00000011,%00000001,%00000001,0 ; XX101011

	.BYTE %00000000,%00000011,%00000001,0 ; XX101100
	.BYTE %00000010,%00000011,%00000001,0 ; XX101101
	.BYTE %00000001,%00000011,%00000001,0 ; XX101110
	.BYTE %00000011,%00000011,%00000001,0 ; XX101111

	.BYTE %00000000,%00000000,%00000011,0 ; XX110000
	.BYTE %00000010,%00000000,%00000011,0 ; XX110001
	.BYTE %00000001,%00000000,%00000011,0 ; XX110010
	.BYTE %00000011,%00000000,%00000011,0 ; XX110011

	.BYTE %00000000,%00000010,%00000011,0 ; XX110100
	.BYTE %00000010,%00000010,%00000011,0 ; XX110101
	.BYTE %00000001,%00000010,%00000011,0 ; XX110110
	.BYTE %00000011,%00000010,%00000011,0 ; XX110111

	.BYTE %00000000,%00000001,%00000011,0 ; XX111000
	.BYTE %00000010,%00000001,%00000011,0 ; XX111001
	.BYTE %00000001,%00000001,%00000011,0 ; XX111010
	.BYTE %00000011,%00000001,%00000011,0 ; XX111011

	.BYTE %00000000,%00000011,%00000011,0 ; XX111100
	.BYTE %00000010,%00000011,%00000011,0 ; XX111101
	.BYTE %00000001,%00000011,%00000011,0 ; XX111110
	.BYTE %00000011,%00000011,%00000011,0 ; XX111111