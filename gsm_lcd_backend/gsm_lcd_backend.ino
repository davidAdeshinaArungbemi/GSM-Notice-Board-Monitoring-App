// code for sending data to lcd and receiving messages from gsm module
//assuming 16x2 LCD => 16 characters per line, 2 lines, 32 characters in total

// ensure baurdate and port are the same

#include <Wire.h>
#include "LiquidCrystal_I2C.h"

LiquidCrystal_I2C lcd1(0x27,  16, 2);
// LiquidCrystal_I2C lcd2(#need address,  16, 2);

String message_lcd1;
String message_lcd2;

void printToLCD(String lcd_message, LiquidCrystal_I2C lcd_id, String &message_lcd_id, int time_delay = 100){
  message_lcd_id = lcd_message.substring(3);
  lcd_id.clear();
  
  for (int i = 0; i < message_lcd_id.length(); i++) {
    if (i == 16){ //first row exceeded
      lcd_id.setCursor(0, 1);

      if (message_lcd_id[i] == " "){
        continue;
      }
    }
    lcd_id.print(message_lcd_id[i]);
    delay(time_delay); //gives a writing effect
  }
}

void updateLCD(){
  String message;
  if (Serial.available() > 0){ //update lcd with new message when available in serial port
    message = Serial.readStringUntil('\n'); //read from serial port
    Serial.println("Received: " + message); //return a response to serial port

    if (message.startsWith("L1:")){
      printToLCD(message,lcd1, message_lcd1);
    }

    // else if (message.startsWith("L2:")){
    //   printToLCD(message,lcd2, message_lcd2);
    // }

    printToLCD(message,lcd1, message_lcd1, 0);
    // printToLCD(message,lcd2, message_lcd2, 0);
  }
}

void setup() {
  Serial.begin(115200); // Initialize serial communication with a baud rate of 9600
  //initialize lcd1 and lcd2 screen
  lcd1.begin();
  // lcd2.begin();

  // turn on the backlight of both lcds
  lcd1.backlight();
  // lcd2.backlight()
}

void loop() {
  updateLCD();
}