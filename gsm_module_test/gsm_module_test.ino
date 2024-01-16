#include <SoftwareSerial.h>

// Create software serial object to communicate with SIM800L
SoftwareSerial gsmSerial(3, 2); // SIM800L Tx & Rx is connected to Arduino #3 & #2

#define MESSAGE_LENGTH 200
#define NULLADDRESS -1
char messageBuffer[MESSAGE_LENGTH];
int bufferAddress = NULLADDRESS;
String strDel = ">";

#include <Wire.h>
#include "LiquidCrystal_I2C.h"

LiquidCrystal_I2C lcd1(0x27, 16, 2);
// LiquidCrystal_I2C lcd2(#need address,  16, 2);

String message_lcd1;

void printToLCD(String lcd_message, LiquidCrystal_I2C lcd_id, String &message_lcd_id, int time_delay = 100)
{
  message_lcd_id = lcd_message.substring(3);
  lcd_id.clear();

  for (int i = 0; i < message_lcd_id.length(); i++)
  {
    if (i == 16)
    { // first row exceeded
      lcd_id.setCursor(0, 1);

      if (message_lcd_id[i] == " ")
      {
        continue;
      }
    }
    lcd_id.print(message_lcd_id[i]);
    delay(time_delay); // gives a writing effect
  }
}

void updateLCD()
{
  String message;
  if (Serial.available() > 0 && Serial.peek() == 'L')
  {                                         // update lcd with new message when available in serial port
    message = Serial.readStringUntil('\n'); // read from serial port
    Serial.println("Received: " + message); // return a response to serial port

    if (message.startsWith("L1:"))
    {
      printToLCD(message, lcd1, message_lcd1);
    }

    // else if (message.startsWith("L2:")){
    //   printToLCD(message,lcd2, message_lcd2);
    // }

    // printToLCD(message, lcd1, message_lcd1, 0);
    // printToLCD(message,lcd2, message_lcd2, 0);
  }
}

// N: => Network
// M: => Message
// L: => LCD
// B: => Battery

void setup()
{
  lcd1.begin();
  // turn on the backlight of lcd
  lcd1.backlight();

  // Begin serial communication with Arduino and Arduino IDE (Serial Monitor)
  Serial.begin(9600);
  // Begin serial communication with Arduino and SIM800L
  gsmSerial.begin(9600);

  Serial.println("<Initialising..." + strDel);

  gsmSerial.println("AT"); // Once the handshake test is successful, it will back to OK
  delay(100);
  Serial.println("<" + gsmSerial.readString() + strDel);

  setNetworkStatus();

  Serial.println("<Ready!>");

  clearBufferAndCounter();
}

void setNetworkStatus()
{
  gsmSerial.println("AT+CSQ"); // Signal quality test, value range is 0-31 , 31 is the best
  delay(100);
  Serial.println("<N:" + gsmSerial.readString() + strDel);

  gsmSerial.println("AT+CCID"); // Read SIM information to confirm whether the SIM is plugged
  delay(100);
  Serial.println("<" + gsmSerial.readString() + strDel);

  gsmSerial.println("AT+CREG?"); // Check whether it has registered in the network
  delay(100);
  Serial.println("<" + gsmSerial.readString() + strDel);

  gsmSerial.println("AT+CMGF=1"); // Configuring TEXT mode
  delay(100);
  Serial.println("<" + gsmSerial.readString() + strDel);

  gsmSerial.println("AT+CNMI=1,2,0,0,0"); // Decides how newly arrived SMS messages should be handled
  delay(100);
  Serial.println("<" + gsmSerial.readString() + strDel);

  gsmSerial.println("AT+CBC");
  delay(100);
  Serial.println("<B:" + gsmSerial.readString() + strDel);
}

String extractCharArray()
{ // converts message in messageBuffer array to String
  String serialMessage = "";
  for (int address = 0; address < bufferAddress + 1; address++)
    serialMessage += messageBuffer[address];
  return serialMessage;
}

void clearBufferAndCounter()
{
  for (int i = 0; i < MESSAGE_LENGTH; i++)
    messageBuffer[i] = '^'; // sets them all to special character

  bufferAddress = NULLADDRESS; // set to -1
}

void sendMessageToSerial(String serialMessage)
{
  Serial.println("<M:" + serialMessage + strDel); // sends String message to serial
  clearBufferAndCounter();                        // clear buffer and reset bufferAddress counter
}

void getGSMData() // get gsm message
{
  // Serial.println(gsmSerial.read());

  if (gsmSerial.available() > 0 && gsmSerial.peek() == '>')
  {
    gsmSerial.read();
    String serialMessage = extractCharArray();
    sendMessageToSerial(serialMessage);
  }

  else if (gsmSerial.available() > 0 && bufferAddress < MESSAGE_LENGTH) // check if message is available, check for end and message length limit
  {
    // Serial.write(gsmSerial.peek());
    bufferAddress++;                                 // increment buffer addresss
    messageBuffer[bufferAddress] = gsmSerial.read(); // store char in buffer address
  }
}

void loop()
{
  getGSMData();
  // delay(200);
  // if (!gsmSerial.available()){
    updateLCD();
  // }
  // gsmSerial.println("AT+CSQ"); // Signal quality test, value range is 0-31 , 31 is the best
  // Serial.println("<N:" + gsmSerial.readString() + strDel);
  // gsmSerial.println("AT+CBC"); // Battery Level
  // Serial.println("<B:" + gsmSerial.readString() + strDel);
  // delay(300);
}
