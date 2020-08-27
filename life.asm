#include "../tmon3.h"
#define PB_LCD_ENABLE
//#define RAM_LOAD
//#define DEBUG
; RIP John Conway (26 December 1937 – 11 April 2020)
#ifdef RAM_LOAD
* = $3100
#else
* = $E000
#endif
CR           = $0D
LF           = $0A
CHAROUT      = $8001
CHARIN       = $8002
RANDOM       = $8003
BUFF1        = $0400        ; buffer 1 (16x16)
BUFF2        = $0500        ; buffer 2 (16x16)
VBL          = $10          ; "active" video buffer
VBH          = $11
BBL          = $12          ; "inactive" background buffer
BBH          = $13
ACTIVE_BUFFER= $14
YTMP         = $15
UBTMP        = $16
TNIB         = $17
CURRENT_CELL = $18
PRL          = $02
PRH          = $03
INF_RUN      = $04
CELL         = "*"
SPACE        = " "
DIVISION     = "-"
RCHR         = "R"
QCHR         = "Q"
ICHR         = "I"
GENERATIONS  = $05
CELL_NEIGHBOR_COUNT = $0


; ---- main
INIT:
lda #$1
sta INF_RUN
MAIN:
    clc
    ldx #$FF
    txs
    jsr print_title
    ldx #<LSTR1
    ldy #>LSTR1
    jsr LCD_CLEAR
    jsr LCD_PRINTS
    jsr init
    jsr gen_rand_board
    ;jsr set_debug_board
main_loop:
    jsr display_buffer
    lda INF_RUN
    beq INPUT_SKIP
    lda #1
    jsr LCD_SET_LINE
    phx
    phy
    ldx #<LSTR2
    ldy #>LSTR2
    jsr LCD_PRINTS
    lda GENERATIONS
    sta NUM_CONV_HEX
    jsr HEX_2_DECS
lcd_write:
    pla
    beq lcd_write_end
    jsr LCD_PUTC
    jmp lcd_write
lcd_write_end:
    ply
    plx
    jsr check_input
INPUT_SKIP:
    jsr update_board
    inc GENERATIONS
    lda GENERATIONS
    cmp #$80
    bne RESET_SKIP
    lda INF_RUN
    beq MAIN
RESET_SKIP:
    jmp main_loop

; ---- subroutines

check_input:
    lda #$0
    ci_fetch:
        lda CHARIN
        beq ci_fetch
        cmp #CR
        beq ci_return
        cmp #ICHR
        beq ci_inf
        cmp #RCHR
        beq MAIN
        cmp #QCHR
        bne ci_fetch
        jmp ($FFFA)
    ci_inf:
        lda #$0
        sta INF_RUN
    ci_return:
        rts

print_title:
    ldx #<TITLE1
    ldy #>TITLE1
    jsr PRINTS
    ldx #<TITLE2
    ldy #>TITLE2
    jsr PRINTS
    ldx #<TITLE3
    ldy #>TITLE3
    jsr PRINTS
    ldx #<TITLE4
    ldy #>TITLE4
    jsr PRINTS
    ldx #<TITLE5
    ldy #>TITLE5
    jsr PRINTS
    rts

#ifdef DEBUG
clear_board:
    ldy #$0
    lda #$0
    cb_loop:
        sta (VBL), y
        sta (BBL), y
        iny
        bne cb_loop
    rts

set_debug_board:
    jsr clear_board
    lda #$01
    ldy #$34            ; load blinker
    sta (VBL), y
    ldy #$44
    sta (VBL), y
    ldy #$54
    sta (VBL), y

    ldy #$0            ; load box
    sta (VBL), y
    iny
    sta (VBL), y
    ldy #$10
    sta (VBL), y
    iny
    sta (VBL), y

    ldy #$c4            ; load glider
    sta (VBL), y
    iny
    sta (VBL), y
    iny
    sta (VBL), y
    ldy #$b6
    sta (VBL), y
    ldy #$a5
    sta (VBL), y
    rts
#endif
    
init:
    lda #<BUFF1
    sta VBL
    lda #>BUFF1
    sta VBH
    lda #<BUFF2
    sta BBL
    lda #>BUFF2
    sta BBH
    lda #$0
    sta GENERATIONS
    rts

delay:
    txa
    pha
    ldx #$FF
    delay_loop:
        dex
        bne delay_loop
    pla
    tax
    rts

new_line:
    lda #LF
    sta CHAROUT
    lda #CR
    sta CHAROUT
    rts


print_division:
    ldy #$10
    lda #DIVISION
    pdl:
        sta CHAROUT
        dey
        bne pdl
    jsr new_line
    rts
    
    
swap_buffers:
    lda VBH
    ldx BBH
    sta BBH
    stx VBH
    rts


; fills a buffer with random numbesr pointed to by VBL,VBH
gen_rand_board:
    ldy #$0
    grb_loop:
        lda RANDOM
        and #$01
        sta (VBL), y
        iny
        bne grb_loop
    rts
        

display_buffer:
    ldy #$0
    db_loop:
        lda (VBL), y
        beq db_dead
        db_alive:
            lda #CELL
            jmp db_out
        db_dead:
            lda #SPACE
        db_out:
        sta CHAROUT
        iny                     ; check if we've printed 16 characters this line
        tya
        and #$0F
        bne db_no_new_line      ; continue if we haven't
        jsr new_line
        db_no_new_line:
        tya
        cmp #$00                ; check if we've reached the end of the buffer
        bne db_loop             ; continue loop if we haven't
        jsr print_division
        rts


; Update Board
;     for each pixel:
;         check and count all neighbors in CELL_NEIGHBOR_COUNT
;             if cell is alive:
;                 1. cell dies if it has less than 2 neighbors
;                 2. cell lives if it has 2 or 3 neighbors
;                 3. cell dies if it has more than 3 neighbors
;             if cell is dead:
;                 1. if cell has exactly 3 neighbors, it becomes alive 
;
; This function reads the current VBL,VBH and generates the new board
; in BBL,BBH.
; This function swaps the pointers before returning, making
; the new board VBL,VBH. (VBL,VBH) will always be the buffer drawn
update_board:
    ldy #$0
    
    ; iterate over each pixel in VBL,VBH
    ub_pixel_loop:
        lda #$0
        sta CELL_NEIGHBOR_COUNT
        sty CURRENT_CELL
         
        ; count upper neighbors
        lda CURRENT_CELL
        sec
        sbc #$10
        sta YTMP            ; go up one row and store middle pixel address in YTMP

        ; count top neighbors
        ldy YTMP
        jsr add_cell        ; top
        lda YTMP
        jsr sub_nibble
        jsr add_cell        ; top left
        lda YTMP
        jsr add_nibble
        jsr add_cell        ; top right

        ; count middle neighbors
        lda CURRENT_CELL
        jsr sub_nibble
        jsr add_cell        ; left
        lda CURRENT_CELL
        jsr add_nibble
        jsr add_cell        ; right
        

        ; count bottom neighbors
        lda CURRENT_CELL
        clc
        adc #$10
        sta YTMP            ; go down one row and store middle pixel address in YTMP
        ldy YTMP
        jsr add_cell        ; bottom
        lda YTMP
        jsr add_nibble
        jsr add_cell        ; bottom right
        lda YTMP
        jsr sub_nibble
        jsr add_cell        ; bottom left


        ; cell logic
        ldy CURRENT_CELL
        lda (VBL), y
        sta (BBL), y
        cmp #$0
        bne is_alive
        is_dead:
            lda CELL_NEIGHBOR_COUNT
            cmp #$3
            bne current_cell_end
            lda #$01
            sta (BBL), y
            jmp current_cell_end
        is_alive:
            lda CELL_NEIGHBOR_COUNT
            cmp #$02
            bmi kill_cell
            cmp #$04
            bcs kill_cell
            jmp current_cell_end
            kill_cell:
                lda #$0
                sta (BBL), y

    current_cell_end:
        ldy CURRENT_CELL
        iny
        beq loop_end
        jmp ub_pixel_loop
loop_end:
    jsr swap_buffers
    rts 

        


; reads the cell passed in Y from VBL
; adds 1 to CELL_NEIGHBOR_COUNT if the cell is alive
add_cell:
    lda (VBL), y
    clc
    beq add_cell_end
    lda #$1
    adc CELL_NEIGHBOR_COUNT
    sta CELL_NEIGHBOR_COUNT
add_cell_end:
    rts
     


; adds 0x01 to the A register RETURNS IN Y 
; must maintain the top nibble and ignore carry
; for example:
;       0x2F + 0x02 = 0x21
add_nibble:
    pha
    and #$F0            ; save the top nibble
    sta TNIB
    pla 
    clc
    adc #$01            ; add 1 to A
    and #$0F            ; clear any carried bits
    ora TNIB            ; restore original top nibble
    tay
    rts
    
; subs a nibble to the A register RETURNS IN Y
; must maintain the top nibble 
; for example:
;       0x20 - 0x02 = 0x2E
sub_nibble:
    pha
    and #$F0
    sta TNIB
    pla
    sec
    sbc #$01
    and #$0F
    ora TNIB
    tay
    rts

TITLE1:  .byte   LF,CR," - Game of Life - TPC65 -",LF,CR,0
TITLE2:  .byte   "In memory of John Conway (1937 - 2020)",LF,CR,0
TITLE3:  .byte   "  [Enter] - Continue to next generation",LF,CR,0
TITLE4:  .byte   "  [R]     - Restart game",LF,CR,0
TITLE5:  .byte   "  [Q]     - Exit",LF,CR,0


#ifdef PB_LCD_ENABLE
LSTR1:  .byte   "Game of Life",0
LSTR2:  .byte   "Generation: ",0
#endif
