#include <WiFi.h>
#include <HTTPClient.h>

// ==========================================
// ALERTO-POZ HARDWARE CONFIGURATION
// ==========================================

// 1. PALITAN ITO NG WIFI NAME AT PASSWORD NIYO:
const char* ssid = "alerto";
const char* password = "12345678";

// 2. PALITAN ITO NG IP ADDRESS NG NODE.JS BACKEND MO
// Halimbawa: "http://192.168.1.10:3000/api/hardware/trigger"
const String serverName = "http://10.99.236.29:3000/api/hardware/trigger";

// ==========================================

const int buttonPin = 16; // GPIO 16 (P16)
int buttonState = HIGH;      // current state of the button
int lastButtonState = HIGH;  // previous state of the button

// Debounce variables to prevent accidental double-clicks
unsigned long lastDebounceTime = 0;  
unsigned long debounceDelay = 50;

void setup() {
  Serial.begin(115200);
  
  // Gamitin ang internal PULLUP resistor para sa GPIO 4
  pinMode(buttonPin, INPUT_PULLUP);

  // Connect to Wi-Fi
  WiFi.begin("alerto", "12345678");
  Serial.println("ALERTO-POZ Hardware System Booting...");
  Serial.print("Connecting to WiFi: ");
  Serial.println(ssid);
  
  while(WiFi.status() != WL_CONNECTED) { 
    delay(500);
    Serial.print(".");
  }
  
  Serial.println("\n✅ Connected to WiFi!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());
  Serial.println("Ready to trigger alerts.");
}

void loop() {
  int reading = digitalRead(buttonPin);

  // Kapag naramdaman na napindot (LOW) at hindi ito yung nakaraang state
  if (reading == LOW && lastButtonState == HIGH) {
    delay(50); // Mabilis na anti-bounce
    
    // I-check ulit kung nakadiin pa rin pagkatapos ng 50ms
    if (digitalRead(buttonPin) == LOW) {
      Serial.println("\n🚨🚨🚨 BUTTON PRESSED! 🚨🚨🚨");
      Serial.println("Sending Emergency Alert to ALERTO-POZ Server...");
      
      // I-send sa backend
      sendAlertToBackend();
      
      // 5 Seconds cooldown para hindi mag-spam ng alert kahit nakadiin
      delay(5000); 
      Serial.println("\nSystem Ready.");
    }
  }

  lastButtonState = reading;
}

void sendAlertToBackend() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    
    // Simulan ang HTTP connection
    http.begin(serverName);
    http.addHeader("Content-Type", "application/json");

    // Payload (Kung ano ang ipapadala natin sa server)
    String httpRequestData = "{\"device_id\":\"ALERTO-DEMO-01\",\"secret_token\":\"demo_secret_key_123\",\"type\":\"Hardware Emergency\"}";           

    // I-send ang POST request
    int httpResponseCode = http.POST(httpRequestData);

    if (httpResponseCode > 0) {
      Serial.print("✅ Server Received Alert! HTTP Response code: ");
      Serial.println(httpResponseCode);
      
      String payload = http.getString();
      Serial.println("Server Reply: " + payload);
    } else {
      Serial.print("❌ Failed to reach server. Error code: ");
      Serial.println(httpResponseCode);
      Serial.println("Check if your backend is running and the IP is correct.");
    }
    
    // Tapusin ang connection
    http.end();
  } else {
    Serial.println("❌ WiFi Disconnected. Cannot send alert.");
  }
}

