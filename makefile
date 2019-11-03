all:   out.hex  
out.hex:  main.asm
	avr-as -mmcu=atmega88 -o i.o main.asm
	avr-objdump -s i.o
	avr-ld -o i.elf  i.o
	avr-objcopy i.elf -O ihex  out.hex
dis: out.hex
	avr-objdump -S i.elf
sim: out.hex
	avrsimu out.hex
clean:
	rm -f *.elf *.o *.hex *- serdriver
	rm -rf serdriver.dSYM
burn:  out.hex
	avrdude -cusbtiny -pm88 -v -U flash:w:out.hex:i
#p287
#p27
fusefry:
	avrdude -cusbtiny -pm88 -v -U lfuse:w:0x27:m 
talk: 
	cu -l /dev/cuaU0 -s 230400

