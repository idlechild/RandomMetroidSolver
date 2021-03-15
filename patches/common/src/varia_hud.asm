;;; VARIA HUD to display current area (in the area randomizer sense),
;;; the split type (M for major, or Z for chozo), and the remaining
;;; number of items of the chozen split in the current area (1 digit
;;; for M/Z, 2 digits in full - no split indicator, and more items)

;;; Includes etank bar combine by lioran

;;; Compile with "asar" (https://github.com/RPGHacker/asar/releases)

!hudposition = #$0006
;;; RAM used to store previous values to see whether we must draw
;;; area/item counter
!previous = $7fff3c		; hi: area, lo: remaining items
;;; RAM for remaining items in current area
!rem_items = $7fff3e
;;; item split written by randomizer
!seed_type = $82fb68
;;; vanilla bit array to keep track of collected items
!item_bit_array = $7ed870
;;; bit index to byte index/bitmask routine
!bit_index = $80818e

lorom

;;; hijack the start of health handling in the HUD to draw area or
;;; remaining items if necessary
org $809B8B
	JSR draw_info

;;; hijack load room state, to init remaining items counter
org $82def7
	jsl load_state

;;; yet another item pickup hijack, different from the ones in endingtotals and bomb_torizo
;;; this one is used to count remaining items in current area
org $8488aa
	jsl item_pickup

;;; the following code will overwrite the normal etank drawing code,
;;; no extra space required, just turn the 2 lines of 14 etank into
;;; 1 lines of combined 14 etanks
org $809B96
	STA $4204
	SEP #$20
	LDA #$64
	STA $4206 
	REP #$30
	LDA #$0000
	STA $14
	LDY #$0007
	TAX
	LDA $4216
	STA $12
	-
	LDA $14 : CLC : ADC #$0064 : STA $14
	ADC #$02BC : STA $16
	INX : INX 
	LDA $09C4
	CMP $14 : BCS +;check if empty
	LDA #$2C0F
	BRA ++
	+
	LDA $09C2
	CMP $16 : BCC +
	LDA #$2C31
	BRA ++
	+
	CMP $14 : BCC +
	LDA #$2831
	BRA ++
	+
	LDA #$3430
	++
	STA $7EC648,x
	DEY
	BNE -
	NOP 
;end of etank row combine

org $80d030
draw_info:
	phx
	phy
	php

	;; determine current graph area
	ldx $07bb
	sep #20
	lda $8f0010,x
	;; check if we must draw it
	cmp !previous
	beq .items
	sta !previous
	rep #20
	;; get text address
	asl : asl : asl : asl
	tay
	;; draw text
	ldx !hudposition
.draw_area_loop:
	lda area_names,y
	beq .end
	sta $7ec602,x
	iny : iny
	inx : inx
	bra .draw_area_loop
.items:
	;; check if we must draw remaining items counter
	sep #20
	lda !previous+1 : cmp !rem_items
	beq .end
	sta !previous+1
	lda !seed_type
	rep #20
	and #$00ff
	cmp #$005a		; 'Z'
	beq .draw_chozo
	cmp #$004d		; 'M'
	beq .draw_major
	;; default to full split: draw remaining item count on 2 digits
	lda !rem_items : jsr draw_two
	bra .end
.draw_chozo:
	lda chozo_split : sta $7ec60e
	bra .draw_items
.draw_major:
	lda major_split : sta $7ec60e
.draw_items:
	lda !rem_items : jsr draw_one
.end:
	plp
	ply
	plx
	lda $09C2 ;original code that was hijacked
	rts

; A=remaining items (2 digits)
draw_two:
	sta $4204
	sep #$20
	lda #$0a
	sta $4206
	pha : pla : pha : pla : rep #$20
	lda $4214 : asl : tay
	lda NumberGFXTable, y
	sta $7ec60e
	lda $4216
draw_one:			; A=remaining items (1 digit)
	asl : tay
	lda NumberGFXTable, y
	sta $7ec610
	rts

;; Normal numbers (like energy/ammo)
NumberGFXTable:
	DW #$0C09,#$0C00,#$0C01,#$0C02,#$0C03,#$0C04,#$0C05,#$0C06,#$0C07,#$0C08

;; Inverse video numbers
;; NumberGFXTable:
;; 	DW #$0C45,#$0C3C,#$0C3D,#$0C3E,#$0C3F,#$0C40,#$0C41,#$0C42,#$0C43,#$0C44

table "tables/hud_chars.txt"

area_names:
	dw "CERES  "
	dw $0000
	dw " CRAT  "
	dw $0000
	dw "GBRIN  "
	dw $0000
	dw "RBRIN  "
	dw $0000
	dw " SHIP  "
	dw $0000
	dw "KRAID  "
	dw $0000
	dw "UNORF  "
	dw $0000
	dw " CROC  "
	dw $0000
	dw "LNORF  "
	dw $0000
	dw "WMARI  "
	dw $0000
	dw "EMARI  "
	dw $0000
	dw " TOUR  "
	dw $0000

major_split:
	dw "M"
chozo_split:
	dw "Z"

cleartable

print "b80 end: ", pc
warnpc $80d1af

org $a1f550
load_state:
	jsl compute_rem_items
	;; hijacked code
	LDX $07BB
	LDA $0003,x
	jml $82DEFD		; resume routine

item_pickup:
	sta $7ED870,x		; hijacked code
compute_rem_items:
	phx
	phy
	lda #$0000 : sta !rem_items ; temporarily used to count collected items in current area
	ldy #$0000		; Y will be used to store number of items in current area
	;; go through loc id list for current area, counting collected items
	;; determine current graph area
	ldx $07bb : lda $8f0010,x
	;; get loc id list index in bank A1 in X
	asl : tax : lda.l locs_by_areas,x : tax
.count_loop:
	lda $a10000,x : and #$00ff
	cmp #$00ff : beq .end
	phx
	jsl !bit_index
	lda !item_bit_array,x : and $05e7
	bne .next
	lda !rem_items : inc : sta !rem_items
.next:
	plx
	iny
	inx
	bra .count_loop
.end:
	;; here, rem_items contain collected items, and Y number of items
	;; rem_items = Y - rem_items
	tya : sec : sbc !rem_items : sta !rem_items
	ply
	plx
	rtl

incsrc "locs_by_areas.asm"

print "a1 end: ", pc
warnpc $a1f6af
