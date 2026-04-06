#include <Arduino.h>
#include <ArduinoBLE.h>
#include <Arduino_BMI270_BMM150.h>
#include <PDM.h>
#include "ble_config.h"
#include "mulaw.h"

// ---------------------------------------------------------------------------
// BLE service and characteristics
// ---------------------------------------------------------------------------
BLEService dogSenseService(DOG_SENSE_SERVICE_UUID);

BLECharacteristic audioChar(AUDIO_CHAR_UUID,
    BLENotify,
    AUDIO_PACKET_BYTES);

BLECharacteristic imuChar(IMU_CHAR_UUID,
    BLENotify,
    IMU_PACKET_BYTES);

BLECharacteristic commandChar(COMMAND_CHAR_UUID,
    BLEWrite | BLEWriteWithoutResponse,
    1);

// ---------------------------------------------------------------------------
// PDM audio buffers (double-buffer to avoid writing from ISR)
// ---------------------------------------------------------------------------
static int16_t pdmRawBuf[AUDIO_PACKET_BYTES];
static uint8_t audioPktBuf[AUDIO_PACKET_BYTES];
static volatile bool audioReady = false;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
static bool streaming = false;
static unsigned long lastImuMs = 0;

// ---------------------------------------------------------------------------
// PDM callback — fires every 10ms with 160 samples at 16kHz
// ---------------------------------------------------------------------------
static void onPDMData() {
    int bytesAvail = PDM.available();
    if (bytesAvail <= 0) return;
    PDM.read(pdmRawBuf, bytesAvail);
    encode_mulaw_buffer(pdmRawBuf, audioPktBuf, bytesAvail / 2);
    audioReady = true;
}

// ---------------------------------------------------------------------------
// Command characteristic event handler
// ---------------------------------------------------------------------------
static void onCommandWritten(BLEDevice central, BLECharacteristic characteristic) {
    if (characteristic.valueLength() == 0) return;
    uint8_t cmd = characteristic.value()[0];
    if (cmd == CMD_START_STREAMING) {
        streaming = true;
        Serial.println("[DogSense] Streaming started");
    } else if (cmd == CMD_STOP_STREAMING) {
        streaming = false;
        Serial.println("[DogSense] Streaming stopped");
    }
}

// ---------------------------------------------------------------------------
// Pack one IMU reading into a 12-byte big-endian packet
// accel in g * 1000 (int16), gyro in dps * 10 (int16)
// ---------------------------------------------------------------------------
static void buildImuPacket(uint8_t* out) {
    float ax, ay, az, gx, gy, gz;

    if (IMU.accelerationAvailable()) IMU.readAcceleration(ax, ay, az);
    else ax = ay = az = 0.0f;

    if (IMU.gyroscopeAvailable()) IMU.readGyroscope(gx, gy, gz);
    else gx = gy = gz = 0.0f;

    int16_t vals[6] = {
        (int16_t)(ax * 1000.0f), (int16_t)(ay * 1000.0f), (int16_t)(az * 1000.0f),
        (int16_t)(gx * 10.0f),  (int16_t)(gy * 10.0f),  (int16_t)(gz * 10.0f),
    };
    for (int i = 0; i < 6; i++) {
        out[i * 2]     = (uint8_t)(vals[i] >> 8);
        out[i * 2 + 1] = (uint8_t)(vals[i] & 0xFF);
    }
}

// ---------------------------------------------------------------------------
// setup
// ---------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    while (!Serial);

    Serial.println("[DogSense] Booting...");

    if (!IMU.begin()) {
        Serial.println("[DogSense] ERROR: IMU init failed");
        while (true) {}
    }

    PDM.onReceive(onPDMData);
    PDM.setBufferSize(PDM_BUFFER_BYTES);
    if (!PDM.begin(1, 16000)) {
        Serial.println("[DogSense] ERROR: PDM init failed");
        while (true) {}
    }

    if (!BLE.begin()) {
        Serial.println("[DogSense] ERROR: BLE init failed");
        while (true) {}
    }

    BLE.setLocalName("DogSense");
    BLE.setAdvertisedService(dogSenseService);
    dogSenseService.addCharacteristic(audioChar);
    dogSenseService.addCharacteristic(imuChar);
    dogSenseService.addCharacteristic(commandChar);
    BLE.addService(dogSenseService);

    commandChar.setEventHandler(BLEWritten, onCommandWritten);
    BLE.advertise();

    Serial.println("[DogSense] Ready — advertising as 'DogSense'");
}

// ---------------------------------------------------------------------------
// loop
// ---------------------------------------------------------------------------
void loop() {
    BLEDevice central = BLE.central();

    if (central) {
        Serial.print("[DogSense] Connected: ");
        Serial.println(central.address());

        while (central.connected()) {
            BLE.poll();

            if (streaming) {
                if (audioReady) {
                    audioReady = false;
                    audioChar.writeValue(audioPktBuf, AUDIO_PACKET_BYTES);
                }

                unsigned long now = millis();
                if (now - lastImuMs >= IMU_INTERVAL_MS) {
                    lastImuMs = now;
                    uint8_t imuPkt[IMU_PACKET_BYTES];
                    buildImuPacket(imuPkt);
                    imuChar.writeValue(imuPkt, IMU_PACKET_BYTES);
                }
            }
        }

        streaming = false;
        Serial.print("[DogSense] Disconnected: ");
        Serial.println(central.address());
    }

    BLE.poll();
}
