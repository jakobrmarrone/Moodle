#pragma once

// ---------------------------------------------------------------------------
// BLE Service and Characteristic UUIDs
// ---------------------------------------------------------------------------
#define DOG_SENSE_SERVICE_UUID     "8d8439b3-ecbc-59a6-8135-1b1cb5623943"
#define AUDIO_CHAR_UUID            "6aefa1e2-d6b9-5cb9-9fcb-4447897212f2"
#define IMU_CHAR_UUID              "66c1f950-3f93-5424-87a2-cfef024bd248"
#define COMMAND_CHAR_UUID          "a5568574-2b7e-578f-b456-a6a54fb175d2"

// ---------------------------------------------------------------------------
// Packet sizes
// ---------------------------------------------------------------------------
// Audio: 160 µ-law encoded bytes = 10ms of 16kHz mono audio (100 notifs/sec)
#define AUDIO_PACKET_BYTES         160

// IMU: 6 x int16_t = 12 bytes [ax, ay, az, gx, gy, gz]
// accel scaled x1000 (divide by 1000.0 for g), gyro scaled x10 (divide by 10.0 for dps)
#define IMU_PACKET_BYTES           12

// PDM buffer: 160 samples x 2 bytes each = 320 bytes
// PDM library delivers 10ms of audio per callback at 16kHz
#define PDM_BUFFER_BYTES           320

// ---------------------------------------------------------------------------
// Streaming control bytes (written to Command characteristic)
// ---------------------------------------------------------------------------
#define CMD_START_STREAMING        0x01
#define CMD_STOP_STREAMING         0x00

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------
// IMU sent every 20ms -> 50Hz
#define IMU_INTERVAL_MS            20
