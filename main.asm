.EQU 	ddrB , 0x04
.EQU 	portB, 0x25
.EQU 	ddrC, 0x27
.EQU 	portC, 0x26
.EQU 	ddrB, 0x24
.EQU 	portD,  0x0b
.EQU 	ddrD,  0x0a
.EQU    status, 0x3f
.EQU 	sph, 0x3e
.EQU 	spl, 0x3d

;; doc2545.pdf
; p57
;_________________________________________________________
; transmit value in any register 
.macro txreg rn
	mov r0, \rn
	rcall txbyte
.endm
.macro txchar arg0
	ldi r16, \arg0
	mov r0, r16
	rcall txbyte
.endm
	
;___________________________________________________vardecl
__ramstart ==  0x0100 
.EQU  rxringstart, __ramstart
.EQU  rxringend, rxringstart + 0x10 
.EQU  transcount , rxringend + 1
.EQU  errcount , rxringend + 2

;___________________________________________________interrupt vectors
.text
.ORG 0x00	
	rjmp init 	; reset
	rjmp isrerr  	; IRO1
	rjmp isrerr 	; irq1
	rjmp isrerr 	; pcint0
	rjmp isrerr 	; pcint1
	rjmp isrerr 	; pcint2
	rjmp isrerr 	; wdt
	rjmp isrerr 	; tim2compa
	rjmp isrerr 	; tim2compb
	rjmp isrerr  	; tim2ov
	reti;  isrerr ;  tim1cap
	reti;  isrerr ;  tim1a
	reti; isrerr ;  tim1b
	reti; isrerr ;  tim1o
	reti ; rjmp isrerr ;  tim0a
	reti ; tim0b should be in set in hardware?
	reti; isrerr  ;tim0overflo
	rjmp isrerr ;  spi
	rjmp isrrx; rjmp isrerr ;  usart rx complete
	reti ; rjmp isrerr ;  usart empty
	reti ; rjmp isrerr ;  usart txcomplete
	rjmp isrerr ;  adc
	rjmp isrerr ;  eerdy
	rjmp isrerr ;  anacomp
	rjmp isrerr ;  twi
	rjmp isrerr ;  spm
.ORG 0x40
isrerr: 
	lds r0, errcount
	inc r0 
	sts errcount, r0
	lds r6, errcount
	breq isrerr_core_tramp
	reti
	isrerr_core_tramp:
		rjmp cmd_coredump ;  about to wrap, dump core on this error
		
init:	 cli
;_______________________ roll out the clock  to 20mhz
	ldi r16, 0 
	ldi r17, 0x80
.EQU clkps, 0x61
	sts clkps, r17 ; satisfy the lockout 
	sts clkps, r16
;_________________________________pin controls
	ldi r16, 0  ;
	out portD, r16
	ldi r16, 0xff 
	 out ddrD, r16  ;all output
	ldi r16 , 0b00001000
	 out ddrB, r16  
;_____________________________________stack init
; XXX is this optional?
.EQU 	ramendlo,  0xfe
.EQU 	ramendhi,  0x04
	ldi r16 ,  ramendhi ; stack setup, hope that's ram I'm talking to 
	out sph, r16
	ldi r16 ,  ramendlo
	out spl, r16
;___________________________________timer 2 setup
.EQU tccr2a , 0xb0
	ldi r16, 0b10100011   ; both channels, fast pwm 
	sts tccr2a , r16

.EQU tccr2b , 0xb1
	ldi r16, 0x06   ; clock select
	sts tccr2b, r16

.EQU ocr2a, 0xb3	
.EQU ocr2b, 0xb4	
	ldi r16, 0x40
	sts ocr2a, r16
	sts ocr2b, r16
	
;  _______________________________________timer 1 setup
.EQU	tccr1b, 0x81	
	ldi r16 ,0x01
	sts tccr1b, r16
.EQU	timsk1, 0x6f	
	ldi r16 ,0x01
	;sts timsk1, r16
; _______________________________________timer0 setup 
.EQU 	tccr0a, 0x044 ; parenthesized contstants are here .. wtf?
	ldi r16, 0xa3    ; ( comba :01 = 2, comb0:1 = 2) (wgm = 3)   waveform setup 
	sts tccr0a, r16
.EQU 	tccr0b, 0x45
	ldi r16, 0x05 ;  ( 0:4) ( cs0:3 = clock select)
	sts tccr0b, r16
.EQU 	timsk0 , 0x6e
	ldi  r16, 0x01 ; ( interupts not required)   
	sts  timsk0, r16
.EQU ocr0b, 0x48
.EQU ocr0a, 0x47
	ldi r16, 0x10
	sts  ocr0b, r16
	sts  ocr0a, r16
;_______________________________________serial setup
.EQU udr, 0xc6
.EQU ubrh,  0xc5
.EQU ubrl,  0xc4
	;//ldi r16 , 64 ; select baud rate with fosc/8/baudrate p199
	;//betterldi r16 , 65 ; select baud rate with fosc/8/baudrate p199
	;//ldi r16 , 10 ; select baud rate with fosc/8/baudrate p199
	ldi r16 , 10 ; select baud rate with fosc/8/baudrate p199
	
	ldi r17,  0x00
	sts ubrl, r16
	sts ubrh , r17
.EQU ucsrb, 0xc1
	ldi r16 , 0x98 ;  recv intr (arm rx and tx)  
	sts ucsrb, r16
.EQU ucsra, 0xc0
	ldi r16 , 0x22
	sts ucsra, r16 ; set hi 2x  speed
	sei 
;;____________________________________________i2c setup
.EQU  twamr, 0xbd
.EQU  twcr, 0xbc
.EQU  twdr, 0xbb
.EQU  twar, 0xba
.EQU  twsr, 0xb9
.EQU  twbr, 0xb8

;;setup baud gen
;; p218 
;; scl  = fosc/ ( 16 + 2(TWBR) - prescaler)
;; 100 khz = 20mhz/16 + 2(TWBR)  , TWBR = 92
;; 400 khz = 20mhz/16 + 2(TWBR)  , TWBR = 17
	ldi r16 ,  17 
	sts twbr, r16
	lds  r16, twcr
	ori r16,  0x04 ;; oops was 0x08
	sts twcr, r16  ; enable twi periph , set twen
	lds r16, portC	 ; pin setup, pullups and input on PC4, PC5
	ori r16, 0x30
	sts portC, r16
	lds r16, ddrC
	andi  r16, ~(0x33)
	sts ddrC, r16
	
; ringbuffer setup X = ringbufferstart
ldi  r27, 01
ldi  r26, 00
;_______________________________________main
txchar 0x82
txchar 'M'
main:  	 
	rjmp main
cmd_coredump:  ;;core dump 
	txchar 0x80
	txchar 'c'
	txchar 'o'
	txchar 'r'
	txreg r0 ; 4
	txreg r1
	txreg r2
	txreg r3
	txreg r4
	txreg r5
	txreg r6
	txreg r7
	txreg r8
	txreg r9
	txreg r10
	txreg r11
	txreg r12
	txreg r13
	txreg r14
	txreg r15
	txreg r16
	txreg r17
	txreg r18
	txreg r19
	txreg r20
	txreg r21
	txreg r22
	txreg r23
	txreg r24
	txreg r25
	txreg r26
	txreg r27
	txreg r28
	txreg r29
	txreg r30
	txreg r31
	txchar 'r';36
	txchar 'a'
	txchar 'm'
	txchar 'd'
	ldi r30, 0
	ldi r31, 1
	core_walkloop: ;; ;40
		ld 	 r0, Z+
		rcall txbyte
		cpi r30, 0xff	
		brne core_walkloop
	txchar 0xaa
	sei
	ldi r16, 0
	ldi r26, 0
	ldi r27, 1
	rjmp init;
;/________________________________________

;; _______________________________________________________________protocol doc
isrrx:	
;;  r1,r2,trace,read:len[4], addrees[8],reg[8], data[8].*
;; system uses, clobers , r25 ,r24 
;; r26,27 X index register , clobbers
	lds r25, udr  	;; store the in byte in the buffe
	st X+, r25 	;; store the in byte in the buffer
	lds  r24, rxringstart
	andi r24, 0x0f ;; mask the low nibble of length ,for length
	;andi r26 , 0x0f ;; also mask the array from groing out of bounds
	cp r26, r24
	breq framecomplete
	reti
	ctramp:
	rjmp cmd_rst	;xxx

framecomplete: ;; clobber r25 for cmd  r24 length cursor , r23 for i2carg pass
	;lds r23, transcount ;; alloc r23 tmp
	;inc r23
	;sts transcount , r23 ;; free r23
	ldi  r26, 0x00;	 zero X reg
	ldi  r27, 0x01;	 zero X reg
	lds r24, rxringstart ;; command+len
	andi r24, 0x0f; mask length into r24 for later
	lds  r25, rxringstart; grab command
	cpi  r25, 0x01; 
	breq cmd_rst
	bst r25, 4; is this read  ?
	brts cmd_read
	;falthrough into write
cmd_write: ;; must be len 3
	ldi  r26, 0x01;	 zero X reg ;inc r26; step past command header	
	ldi  r27, 0x01;	 zero X reg
	rcall i2start
	subi r24, 3 ;; adjust length counter for the header
	ld r23, X+
	rcall i2tx
	txchar 0x81 ;; talkback  as soonas we get an address lock ack
	ld r23, X+
	rcall i2tx
	cmd_write_walkloop:
		ld r23, X+
		;txchar 'd' xxx
		rcall i2tx
		dec r24
		brne cmd_write_walkloop
	rcall i2stop
	ldi r26, 0 
	ldi r27, 1 
	reti 
	
cmd_read: ;; cmd readlen  must be at least len 3
	lds r23, rxringstart;
	ori 	r23, 0x80
	txreg r23 ;; talkback with header, length
	rcall i2start 
	lds r23, rxringstart+1 ;; address
	;txreg r23 ;; talkback with address
	rcall i2tx
	lds r23 , rxringstart+2;; reg 
	rcall i2tx
	rcall i2start
	lds r23, rxringstart+1 ;; address
	ori r23, 0x01;;  set address high for read
	;txreg r23 ;;  xxx
	push r23; clobbers r23, but I knew that
	rcall i2tx ; clobbers r23, but I knew that
	pop r23
	subi 24, 3 ;; cursor step past cmd, addr , addr+r
	cmd_read_walkloop:
		;txchar 'd' ;; xxx
		rcall i2rx 
		txreg r23  ;; uart and twi can run in parallel a little
		dec r24  
		brne cmd_read_walkloop	
	rcall i2stop
	ldi r23, 0x00	;; workaround for lockup sillicon bug
	sts twcr,  r23 ;; reset twi
	ldi r23, 0x04	;; workaround for lockup sillicon bug
	sts twcr,  r23 ;; reset twi
	ldi r26, 0 
	reti
cmd_rst:
	ldi r26,0 ; reset X
	rjmp cmd_coredump
	ret
i2start: ;; clobbers r23
	ldi r23, twsr
	;txchar 's'
	;txreg r23
	ldi r23, 0xa4 ;;p236
	sts twcr, r23
	i2startwait:
		lds r23, twsr
		cpi r23, 0xF8
		breq i2nostarterr
		cpi r23, 0x08
		breq i2nostarterr
		cpi r23, 0x10
		breq i2nostarterr
		rjmp i2err	
		i2nostarterr:
		lds r23, twcr
		bst r23, 7
		brtc i2startwait
	lds r23 , twsr
	subi r23, 0x08 ; magic  225	
	ret
	lds r23 , twsr ;; start failed!!!!!!!
	rjmp i2err;
	ret	

i2stop:  ;; clober r23
	;txchar 'p' ;xxx
	ldi r23, 0x14 ;;magic p236
	sts twcr , r23
	i2stopwait:
		lds r23, twcr
		bst r23, 7
		brtc i2stopwait
	ret
i2tx: ;; transmits contents of r23 on i2c bus, clobbers r23
	;; consider clobbering r0 instead to fix the pushpop in i2rx
	sts twdr, r23
	ldi r23, 0x84 ;; magic p236
	sts twcr, r23
	i2txwait:
		lds r23, twcr
		bst r23, 7
		brtc i2txwait
	lds r23, twsr
	cpi r23, 0x28 ; magic on p225   data+ack
	breq i2txok
	lds r23, twsr
	cpi  r23, 0x18 ; magic on p225   sla+w+ack
	breq i2txok
	cpi r23 , 0x40 ;  magic 228 sla+r ack used in i2rx
	breq i2txok;
	lds r23, twsr;	
	rjmp i2err;
	i2txok:
	ret

i2rx:  ;; returns data byte in r23
	ldi r23, 0xee ; total trash
	sts twdr, r23 ; load twdr with trash
	ldi r23, 0xC4 ;  magic bullet ;; need bit 6 too to generate ack
	sts twcr, r23  ;
	i2getwait:
		lds r23, twcr
		bst r23, 7
		brtc i2getwait
	lds r23, twsr
	cpi r23, 0x50 ; status recvd ok p228	
	breq i2getdone 
	rjmp i2err;
	i2getdone:
	lds r23, twdr
	ret

i2err:
	txchar 0x85
	txchar 'i'
	txchar '2'
	txchar 'e'
	txreg r23	
	rjmp cmd_coredump
	ret 
;___________________________________________________________________
; r0  as arg to transmit on rs232
; r1 as tmp, clobbers
txbyte:
	txbspin:  
		lds r1 , ucsra 
		bst r1, 5 ; is udr empty? p191
		brtc txbspin
	sts udr, r0
	ret 
