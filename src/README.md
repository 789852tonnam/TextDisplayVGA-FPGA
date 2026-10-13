# FPGA Text Marquee

โปรเจกต์ Verilog สำหรับจอ VGA 640×480 มีโหมด EDIT สำหรับแก้ข้อความ และ SLIDE สำหรับป้ายไฟเลื่อน โดยใช้ top module `tt_um_vga_example` กับ VGA Playground

## ปุ่มควบคุม

| ปุ่ม | การทำงานใน EDIT |
| --- | --- |
| D-pad | เลื่อน cursor ครั้งละหนึ่งช่อง |
| B | อ่าน ASCII จาก RAM ของช่องนั้น แล้วเพิ่ม `A → B → … → Z → A`; ช่องว่างเริ่มที่ A |
| A | เขียนช่องว่าง ASCII `0x20` ลงช่องปัจจุบัน |
| Select | วาง `<` ครั้งแรก แล้ววาง `>` ครั้งที่สอง; เมื่อเลือกครบแล้ว กดอีกครั้งเพื่อเริ่มช่วงใหม่ |
| Start | เข้า SLIDE เมื่อเลือกช่วงครบ; กดอีกครั้งใน SLIDE เพื่อกลับ EDIT |
| Reset | กลับ EDIT, ย้าย cursor ไป (0,0), และล้างสถานะการเลือกช่วง |

ปุ่มทำงานครั้งเดียวตอนเริ่มกด การกดค้างไม่ทำให้ทำงานซ้ำ ใน SLIDE จะหยุดแก้ RAM และซ่อน cursor

## เลือกข้อความที่จะเลื่อน

1. เขียนข้อความในแถวเดียวกัน โดยเว้นช่องสำหรับเครื่องหมายก่อนและหลังข้อความ
2. ย้าย cursor ไปช่องก่อนตัวแรก แล้วกด Select เพื่อวาง `<`
3. ย้าย cursor ไปช่องหลังตัวสุดท้าย แล้วกด Select เพื่อวาง `>`
4. กด Start เพื่อเข้า SLIDE

ตัวอย่าง `<HELLO FPGA>` จะเลื่อนเฉพาะ `HELLO FPGA` ไม่รวมตำแหน่งเครื่องหมาย

`>` ต้องอยู่แถวเดียวกับ `<` และอยู่ทางขวาห่างอย่างน้อยสองช่อง เพื่อให้มีตัวอักษรอยู่ระหว่างเครื่องหมายอย่างน้อยหนึ่งช่อง ตำแหน่งที่อยู่ก่อน `<`, ทับกัน, ติดกัน หรืออยู่คนละแถวจะถูกปฏิเสธ การวาง `<` ต้องเหลือพื้นที่สำหรับข้อความและ `>` ด้วย

เครื่องหมายเป็นภาพวาดทับจอ ไม่ได้เขียนทับ RAM ข้อความใต้เครื่องหมายยังอยู่ แต่ช่องที่เป็นตำแหน่งเครื่องหมายจะไม่ถูกนำไปเลื่อน

## หลักการวงจร

### EDIT และ RAM

EDIT แสดงกริด 80×30 ช่อง ฟอนต์เดิมมีขนาด 8×16 พิกเซล RAM เก็บรหัส ASCII ขนาด 7 บิต จำนวน 4096 ช่อง ที่อยู่ช่องคือ `{row[4:0], column[6:0]}` ดังนั้นแต่ละแถวมี stride 128 ช่อง

ปุ่ม B เพิ่มค่าจาก `memory[wr_adr]` ของตำแหน่ง cursor โดยตรง ไม่มีตัวนับตัวอักษรส่วนกลาง รหัสที่อยู่นอก A–Y รวมถึง Z จะเปลี่ยนเป็น A

RAM มีค่าตั้งต้นเป็นศูนย์ ซึ่ง font ROM แสดงเป็นช่องว่าง `initial` นี้ทำครั้งเดียวตอนเริ่มต้น; Reset ไม่ล้างข้อความที่เขียนไว้ RAM ใช้การอ่านแบบ asynchronous สำหรับ cursor/เติมคิว และอ่านแบบ synchronous สำหรับ VGA โดย Vivado สังเคราะห์เป็น distributed RAM จาก LUT

### SLIDE และคิว 11 ตัว

- ขยายฟอนต์ 8 เท่า เป็นตัวละ 64×128 พิกเซล
- จอกว้าง 640 พิกเซลแสดงได้ 10 ตัวเต็ม และใช้ตัวที่ 11 รองรับขอบที่กำลังเลื่อนเข้าจอ
- เก็บรหัส ASCII 11 ตัวใน `slide_buffer[0:10]`
- `slide_phase_reg` นับ 0–7 แทนระยะเลื่อน 0, 8, 16, …, 56 พิกเซล
- เมื่อครบ 8 จังหวะหรือ 64 พิกเซล จะดันคิวหนึ่งช่องและเติมตัวถัดไปจาก RAM
- อ่านวนเฉพาะช่วงด้านใน `< >`; ข้อความที่สั้นกว่า 11 ตัวจะวนซ้ำเพื่อเติมคิว
- เติมคิวและปรับระยะเลื่อนช่วง vertical blanking เพื่อลดภาพฉีก
- ตัวอักษรอยู่กึ่งกลางแนวตั้ง ตั้งแต่ y=176 ถึง y=303

ค่าเริ่มต้น `SLIDE_STEP_FRAMES = 4` คือเลื่อน 8 พิกเซลทุก 4 เฟรม ปรับความเร็วด้วย parameter นี้ใน `19_text_screen_gen_playground.v` และปรับตำแหน่งแนวตั้งด้วย `SLIDE_TOP`

### FSM

| FSM | State |
| --- | --- |
| โหมดหลัก | `EDIT`, `SLIDE` |
| การเลือกช่วง | `SEL_NONE` ยังไม่เลือก, `SEL_END` รอ `>`, `SEL_READY` เลือกครบ |

การเติมคิวใช้ flag `slide_loading_reg`, `slide_ready_reg` และ counter แยกจาก FSM ทั้งสองชุด

## ไฟล์สำคัญ

| ไฟล์ | หน้าที่ |
| --- | --- |
| `19_top_SwitchTextDisplay_playground.v` | เชื่อม gamepad, VGA sync และวงจรข้อความ; คาดการณ์ตำแหน่งล่วงหน้า 2 clock |
| `19_text_screen_gen_playground.v` | EDIT/SLIDE, เลือกช่วง, คิว และการวาดข้อความ |
| `13_simpledualportMem.v` | RAM เก็บ ASCII และพอร์ตอ่าน cursor |
| `19_ascii_rom_playground.v` | Font ROM ของ ASCII ขนาด 8×16 |
| `gamepad_pmod.v` | รับและถอดรหัสสถานะ gamepad จาก serial data/clock/latch |
| `hsync_generator.v` | สร้าง VGA timing 640×480 |
| `10_debounce.v` | โมดูลเดิมที่เก็บไว้; วงจรปัจจุบันจับขอบสถานะ gamepad โดยตรงและไม่ได้ใช้โมดูลนี้ |

Gamepad ใช้ `ui_in[4]` เป็น latch, `[5]` เป็น serial clock และ `[6]` เป็น data ส่วน gamepad vector ภายในเรียง `{B,Y,Select,Start,Up,Down,Left,Right,A,X,L,R}`

## รันบน VGA Playground

1. จาก root ของ repository รัน `python3 playground/build_bundle.py` เมื่อมีการแก้ src
2. เปิด https://vga-playground.com/?preset=gamepad
3. คัดลอกทั้งไฟล์ `playground/project.v` ไปแทนแท็บ `project.v` ของเว็บ
4. เก็บแท็บ `gamepad_pmod.v` และ `hvsync_generator.v` ของ preset ไว้
5. เปิด Gamepad Mode แล้วกด Reset ก่อนใช้งาน

อีกทางหนึ่ง หลังนำ repository ขึ้น GitHub แล้ว สามารถเปิด `https://vga-playground.com/?repo=https://github.com/USER/REPO` ได้ โดย `info.yaml` ที่ root ระบุไฟล์ซอร์สใน `src/` ให้เว็บโหลด

โค้ด top ใช้ interface ของ VGA Playground/Tiny Tapeout การนำลงบอร์ด FPGA จริงต้องจัด clock และ pin constraints ให้ตรงบอร์ดด้วย

## ทดสอบ

ต้องมี Vivado Simulator (`xvlog`, `xelab`, `xsim`), Python 3 พร้อม Pillow และ `rg`

จาก root ของ repository:

```bash
bash tests/run_tests.sh
```

ถ้าไม่ได้ตั้ง Vivado ไว้ใน PATH ให้กำหนดโฟลเดอร์ bin ของ installation:

```bash
VIVADO_BIN=/path/to/Vivado/bin bash tests/run_tests.sh
```

- `tb_marquee.v` ตรวจปุ่ม, ช่วงที่ไม่ถูกต้อง, overlay, คิว, การวนข้อความ, จังหวะเลื่อน, การกลับ EDIT และ Reset
- `tb_marquee_render.v` เก็บ RGB จาก top จริงที่เฟส 0, เฟส 7 และหลังดันคิว
- `check_marquee_pixels.py` เทียบทุกพิกเซลของภาพ 640×480 ทั้งสามภาพกับ font ROM และตำแหน่งที่คาดไว้

ผลและ log จะอยู่ในโฟลเดอร์ชั่วคราวที่ script แจ้งเมื่อจบ ไม่เขียนทับไฟล์ซอร์ส ภาพตัวอย่างจาก simulation อยู่ใน `playground/previews/`

## ที่มา

Font/text rendering พัฒนาต่อจาก FPGA Prototyping by Verilog Examples ของ Pong P. Chu และโค้ดที่ปรับสำหรับ Basys 3/VGA Playground รายละเอียดเครดิตอยู่ในส่วนหัวไฟล์ซอร์ส

Gamepad PMOD มาจาก Pat Deegan / Psychogenic: https://github.com/psychogenic/gamepad-pmod โดยคงข้อความ copyright และ SPDX license ในซอร์สไว้
