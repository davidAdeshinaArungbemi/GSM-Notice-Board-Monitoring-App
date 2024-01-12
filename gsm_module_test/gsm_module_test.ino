#include <SoftwareSerial.h>

//Create software serial object to communicate with SIM800L
SoftwareSerial gsmSerial(3, 2); //SIM800L Tx & Rx is connected to Arduino #3 & #2

#define MESSAGE_LENGTH 200
#define NULLADDRESS -1
char messageBuffer[MESSAGE_LENGTH];
int bufferAddress = NULLADDRESS;
String strDel = ">";

// N: => Network
// M: => Message
// L: => LCD

void setup()
{
  //Begin serial communication with Arduino and Arduino IDE (Serial Monitor)
  Serial.begin(9600);
  //Begin serial communication with Arduino and SIM800L
  gsmSerial.begin(9600);
  // delay(1000);

  Serial.println("Initialising..."+strDel); 

  gsmSerial.println("AT"); //Once the handshake test is successful, it will back to OK
  Serial.println(gsmSerial.readString()+strDel);

  setNetworkStatus();

  clearBufferAndCounter();//fill with '>'
  // gsmSerial.println("AT+CBC");
  // Serial.println(gsmSerial.readString());
  // gsmSerial.println("AT+GMI");
  // Serial.println(gsmSerial.readString());
  // gsmSerial.println("AT+GMM");
  // Serial.println(gsmSerial.readString());
  // gsmSerial.println("AT+GMR");
  // Serial.println(gsmSerial.readString());
  Serial.println("Ready!"+strDel);
}

void setNetworkStatus(){
  gsmSerial.println("AT+CSQ");//Signal quality test, value range is 0-31 , 31 is the best
  Serial.println("N:"+gsmSerial.readString()+strDel);

  gsmSerial.println("AT+CCID"); //Read SIM information to confirm whether the SIM is plugged
  Serial.println(gsmSerial.readString()+strDel);

  gsmSerial.println("AT+CREG?"); //Check whether it has registered in the network
  Serial.println(gsmSerial.readString()+strDel);
  
  gsmSerial.println("AT+CMGF=1"); // Configuring TEXT mode
  Serial.println(gsmSerial.readString()+strDel);

  gsmSerial.println("AT+CNMI=1,2,0,0,0"); // Decides how newly arrived SMS messages should be handled
  Serial.println(gsmSerial.readString()+strDel);

  gsmSerial.println("AT+CBC");
  Serial.println(gsmSerial.readString());
}

String extractCharArray(){ //converts message in messageBuffer array to String 
  String serialMessage = "";
  for (int address = 0; address < bufferAddress + 1; address++)
    serialMessage += messageBuffer[address];
  return serialMessage;
}

void clearBufferAndCounter(){
  for(int i = 0; i < MESSAGE_LENGTH;i++)
    messageBuffer[i] = '>'; //sets them all to newline 

  bufferAddress = NULLADDRESS; //set to -1
}

void sendMessageToSerial(String serialMessage){
  Serial.println("M:"+serialMessage+strDel); //sends String message to serial
  clearBufferAndCounter(); //clear buffer and reset bufferAddress counter
}

void getGSMData() //get gsm message
{
  // delay(500);
  // Serial.println(gsmSerial.read());
  if (gsmSerial.available() && bufferAddress < MESSAGE_LENGTH) //check if message is available, check for end and message length limit
  {
    // Serial.write(gsmSerial.peek());
    bufferAddress++;//increment buffer addresss
    messageBuffer[bufferAddress] = gsmSerial.read(); //store char in buffer address
  }
  else if (gsmSerial.peek() == '>') {
    String serialMessage = extractCharArray();
    sendMessageToSerial(serialMessage);
  }
}

void loop()
{
  getGSMData();
  // delay(300);
}
