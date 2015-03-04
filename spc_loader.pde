//Arduinoにはあらかじめ、SNES_APU.ino(以下のサイトで公開)を書き込んでおく。
//SPC700との配線方法は、SNES_APU.ino 内に記述されている。
//http://www.caitsith2.com/snes/apu.htm

import processing.serial.*;

Serial port;

char boot_code[] =
{
  /*
  Apuplayのソースより
  
   mov   $00,#($0000)
   mov   $01,#($0001)
   mov   $fc,#($00fc(T2))
   mov   $fb,#($00fb(T1))
   mov   $fa,#($00fa(T0))
   mov   $f1,#($00f1)
   mov   x,#$53
   mov   $f4,x
-  mov   a,$f4
   cmp   a,#($00f4(P0))  //P0セット待ち
   bne   -
-  mov   a,$f5
   cmp   a,#($00f5(P1))  //P1セット待ち
   bne   -
-  mov   a,$f6
   cmp   a,#($00f6(P2))  //P3セット待ち
   bne   -
-  mov   a,$f7
   cmp   a,#($00f7(P3))  //P3セット待ち
   bne   -
   mov   a,$fd
   mov   a,$fe
   mov   a,$ff
   mov   $f2,#$6c
   mov   $f3,#$(DSP$6c)
   mov   $f2,#$4c
   mov   $f3,#$(DSP$4c)
   mov   $f2,#($00f2)
   mov   x,#(SP-3)
   mov   sp,x
   mov   a,#(A)
   mov   y,#(Y)
   mov   x,#(X)
   reti
   */
  0x8F, 0x00, 0x00, 0x8F, 0x00, 0x01, 0x8F, 0xFF, 0xFC, 0x8F, 0xFF, 0xFB, 0x8F, 0x4F, 0xFA, 0x8F, 
  0x31, 0xF1, 0xCD, 0x53, 0xD8, 0xF4, 0xE4, 0xF4, 0x68, 0x00, 0xD0, 0xFA, 0xE4, 0xF5, 0x68, 0x00, 
  0xD0, 0xFA, 0xE4, 0xF6, 0x68, 0x00, 0xD0, 0xFA, 0xE4, 0xF7, 0x68, 0x00, 0xD0, 0xFA, 0xE4, 0xFD, 
  0xE4, 0xFE, 0xE4, 0xFF, 0x8F, 0x6C, 0xF2, 0x8F, 0x00, 0xF3, 0x8F, 0x4C, 0xF2, 0x8F, 0x00, 0xF3, 
  0x8F, 0x7F, 0xF2, 0xCD, 0xF5, 0xBD, 0xE8, 0xFF, 0x8D, 0x00, 0xCD, 0x00, 0x7F,
};

byte  spc_header[];
byte  spc_ram[];
byte  spc_dspreg[];
byte  spc_unused[];
byte  spc_exram[];

int   bootptr;

int   start_addr;
int   write_len;
int   write_progress;
int   wrote_bytes;

void setup() {
  size(400, 64);

  String portName = Serial.list()[8];
  port = new Serial(this, portName, 115200);
  println(portName);
  waitReady();
  
  write_len = 0;
  noLoop();
}

void waitReady() {
  String val = "";
  port.clear();
  while ( val.startsWith ("SPC700 DATA LOADER V1.0") == false ) {
    port.write('S');
    delay(100);
    if ( port.available() > 0) {
      val = port.readStringUntil('\n');
    }
  }
}

void draw()
{
  if ( write_len == 0 ) {
    selectInput("Select a SPC file:", "fileSelected");
  }
  else {
    writeRamTask();
  }
}

void fileSelected(File selection) {
  int i, j=0;

  if (selection == null) {
    println("canceled.");
    noLoop();
    exit();
  }
  else {
    println("Select file: " + selection.getAbsolutePath());
    spc_header = new byte[256];
    spc_ram = new byte[65536];
    spc_dspreg = new byte[128];
    spc_unused = new byte[64];
    spc_exram = new byte[64];
    InputStream input = createInput(selection.getAbsolutePath());
    try {
      input.read(spc_header);
      input.read(spc_ram);
      input.read(spc_dspreg);
      input.read(spc_unused);
      input.read(spc_exram);
    }
    catch (IOException e) {
      e.printStackTrace();
    }
    finally {
      try {
        input.close();
      }
      catch (IOException e) {
        e.printStackTrace();
      }
    }

    //ファイルチェック
    char file_header[] = new char[31];
    for (i=0; i<file_header.length; i++) {
      file_header[i] = char(spc_header[i]);
    }
    String file_header_str = new String(file_header);
    if ( file_header_str.startsWith("SNES-SPC700 Sound File Data v0.") == false ) {
      println("Not a SPC file.");
      noLoop();
      exit();
    }

    byte PCL = spc_header[0x25];
    byte PCH = spc_header[0x26];
    byte A = spc_header[0x27];
    byte X = spc_header[0x28];
    byte Y = spc_header[0x29];
    byte SW = spc_header[0x2a];
    byte SP = spc_header[0x2b];
    int PC = char(PCL)+((char(PCH)<<8)&0xff00);
    println("PC="+hex(PC, 4));
    println("A="+hex(A));
    println("X="+hex(X));
    println("Y="+hex(Y));
    println("PSW="+hex(SW));
    println("SP="+hex(SP));

    println("SPC file load OK.");

    int echo_clear=1;

    //Extra RAM領域が有効ならram内に移動する
    if ( spc_ram[0xf1] < 0 ) {
      for (i=0;i<64;i++) {
        spc_ram[0xffc0+i] = spc_exram[i];
      }
      println("Have exram.");
    }
    else {
      println("No exram.");
    }

    //エコー領域を0で埋める
    int echo_region;
    int echo_size;
    echo_region = char(spc_dspreg[0x6d]) << 8;
    echo_size = (spc_dspreg[0x7d] & 0x0f) * 2048;
    println("echo_region="+hex(echo_region, 4));
    println("echo_size="+hex(echo_size, 4));
    if (echo_size==0) echo_size=4;
    if ( (((spc_dspreg[0x6C] & 0x20)==0)&&(echo_clear==0))||(echo_clear==1) ) {
      for (i=echo_region;(i<0x10000)&&(i<echo_region+echo_size);i++) {
        spc_ram[i]=0;
      }
    }
    println("echo clear OK.");

    //エコー領域を除いた領域で同じ値が77byte以上続く場所にブートローダーを仕込む
    int count=0;
    for (i=255;i>=0;i--) {
      count=0;
      for (j=0xffbf;j>=0x100;j--) {
        if ((j>(echo_region+echo_size))||(j<echo_region)) {
          if (char(spc_ram[j])==i) {
            count++;
          }
          else {
            count=0;
          }
          if (count==boot_code.length) {
            break;
          }
        }
        else {
          count=0;
        }
      }
      if (count==boot_code.length) {
        break;
      }
    }
    if (j==0xff) {
      if (echo_size<boot_code.length) {
        println("Not enough RAM for boot code.");
        noLoop();
        exit();
      }
      else {
        //見つからなければエコー領域を使う
        println("Not found space area. Use echo area");
        j=echo_region;
        count=boot_code.length;
      }
    }
    for (i=j;i<(j+count);i++) {
      spc_ram[i] = byte(boot_code[i-j]);
    }

    spc_ram[j+0x19] = spc_ram[0xF4];
    spc_ram[j+0x1F] = spc_ram[0xF5];
    spc_ram[j+0x25] = spc_ram[0xF6];
    spc_ram[j+0x2B] = spc_ram[0xF7];
    spc_ram[j+0x01] = spc_ram[0x00];
    spc_ram[j+0x04] = spc_ram[0x01];
    spc_ram[j+0x07] = spc_ram[0xFC];
    spc_ram[j+0x0A] = spc_ram[0xFB];
    spc_ram[j+0x0D] = spc_ram[0xFA];
    spc_ram[j+0x10] = spc_ram[0xF1];
    spc_ram[j+0x38] = spc_dspreg[0x6C];
    spc_dspreg[0x6C] = 0x60;
    spc_ram[j+0x3E] = spc_dspreg[0x4C];
    spc_dspreg[0x4C] = 0x00;
    spc_ram[j+0x41] = spc_ram[0xF2];
    spc_ram[j+0x44] = byte(SP - 3);
    spc_ram[0x100 + char(SP) - 0] = PCH;    //符号に注意
    spc_ram[0x100 + char(SP) - 1] = PCL;    //符号に注意
    spc_ram[0x100 + char(SP) - 2] = SW;     //符号に注意
    spc_ram[j+0x47] = A;
    spc_ram[j+0x49] = Y;
    spc_ram[j+0x4B] = X;

    bootptr=j;

    println("bootloader located "+hex(bootptr, 4));

    //SPC700のリセット
    int  val;
    port.clear();
    port.write('s');
    port.write("D0");

    println("reset OK.");

    //ゼロページとDSPレジスタを転送
    port.write('G');
    for (i=0;i<128;i++) {
      val = spc_dspreg[i];
      port.write(val);
    }
    for (i=0;i<256;i++) {
      val = spc_ram[i];
      port.write(val);
    }
    do {
      while (port.available () <= 0 );
      val = port.read();
    } 
    while ( val != 'F' );
    println("dspreg, zeropage OK.");

    //ゼロページ以降のRAMを転送開始
    start_addr = 0x100;
    write_len  = spc_ram.length - start_addr;
    write_progress = 0;
    wrote_bytes = 0;

    port.write('F');
    port.write(start_addr>>8);
    port.write(start_addr&0xff);
    port.write(write_len>>8);
    port.write(write_len&0xff);
    
    loop();
  }
}

void writeRamTask()
{
  byte writedata[] = new byte[64];
  int val;

  if (wrote_bytes<write_len) {
    while (wrote_bytes<write_len) {
      for (int j=0; j<writedata.length; j++) {
        writedata[j] = spc_ram[wrote_bytes+start_addr+j];
      }
      port.write(writedata);

      int temp = (wrote_bytes*100)/write_len;
      wrote_bytes += writedata.length;
      if ( temp != write_progress ) {
        write_progress = temp;
        strokeWeight(0);
        fill(#5CBCCB);
        rect(0, 0, (write_progress*width)/100, height);
        //print(write_progress+"%.");
        break;
      }
    }
  }
  else {
    noLoop();
    do {
      while (port.available () <= 0 );
      val = port.read();
    } 
    while ( val != 1 );
    println("spc_ram OK.");
    jumpToBootloader();
    exit();
  }
}

void jumpToBootloader()
{
  int val;
  //ブートローダーへジャンプ
  if (port.available() > 0 ) {
    port.clear();
  }
  writePort(3, bootptr>>8);
  writePort(2, bootptr&0xff);
  writePort(1, 0);
  val = readPort(0);
  val = (val+2)&0xff;
  writePort(0, val);
  //ブートローダ0xf4<-0x53待ち
  waitPortValue(0, 0x53);
  //ポートを復元
  writePort(0, spc_ram[0xf4]);
  writePort(1, spc_ram[0xf5]);
  writePort(2, spc_ram[0xf6]);
  writePort(3, spc_ram[0xf7]);

  println("PC Port OK.");
}

void writePort(int addr, int value)
{
  port.write('W');
  port.write('0'+(addr&0x0f));
  port.write(value);
}

int readPort(int addr)
{
  int  val;
  port.write('R');
  port.write('0'+(addr&0x0f));
  while (port.available () <= 0 );
  val = port.read();
  return val;
}

void waitPortValue(int addr, int value)
{
  int  val;
  do {
    port.write('R');
    port.write('0'+(addr&0x0f));
    while (port.available () <= 0 );
    val = port.read();
  } 
  while ( val != value );
}

