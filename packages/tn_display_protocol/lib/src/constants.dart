/// Wire constants of protocol v1. Mirrors core/codec/protocol.cpp and
/// firmware/components/transport_ble/ble_uuids.h; the golden vectors keep them honest.
library;

/// Protocol version carried in key 0 of every CBOR map.
const int protocolVersion = 1;

/// Largest CBOR payload on the State / Event / Settings / UiConfig characteristics
/// (fits a 247-byte ATT MTU).
const int maxPayloadBytes = 244;

/// GATT UUIDs. The base is FINAL for protocol v1 (docs/ble-protocol.md) and defined in
/// exactly this one place on the app side.
const String uuidBaseSuffix = 'd673-469c-98a0-12c0c5eb43b3';
const String uuidBasePrefix = '079a';

/// `079aXXXX-d673-469c-98a0-12c0c5eb43b3` for a 16-bit slot.
String uuidForSlot(int slot) =>
    '$uuidBasePrefix${slot.toRadixString(16).padLeft(4, '0')}-$uuidBaseSuffix';

abstract final class Slot {
  static const int service = 0x0000;
  static const int state = 0x0001; // app -> device, write without response
  static const int event = 0x0002; // device -> app, notify
  static const int deviceInfo = 0x0003; // read
  static const int settings = 0x0004; // read / write / notify
  static const int time = 0x0005; // write
  static const int uiConfig = 0x0006; // read / write / notify
  static const int ota = 0x0007; // write without response / notify
  static const int asset = 0x0008; // write without response / notify
}

/// DeviceInfo capability bits (key 2).
abstract final class Caps {
  static const int audio = 1 << 0;
  static const int imu = 1 << 1;
  static const int rtc = 1 << 2;
  static const int sd = 1 << 3;
  static const int speedcamBuild = 1 << 4;
  static const int ota = 1 << 5;
}

/// HazardType values (frozen for v1). Values above [maxKnown] render a generic icon.
abstract final class HazardType {
  static const int fixedSpeedCamera = 0;
  static const int mobileSpeedCamera = 1;
  static const int trailerCamera = 2;
  static const int redLightCamera = 3;
  static const int distanceControl = 4;
  static const int traffic = 5;
  static const int ice = 6;
  static const int accident = 7;
  static const int construction = 8;
  static const int breakdown = 9;
  static const int obstacle = 10;
  static const int maxKnown = 10;

  /// Speed-camera group (ids 0-4): only present when [Caps.speedcamBuild] is set.
  static bool isSpeedCamera(int v) => v >= 0 && v <= 4;
}

abstract final class SpeedUnit {
  static const int kmh = 0;
  static const int mph = 1;
}

abstract final class AudioMode {
  static const int tones = 0;
  static const int voice = 1;
}

abstract final class AudioEvent {
  static const int hazardApproach = 0;
  static const int hazardImminent = 1;
  static const int confirmPrompt = 2;
  static const int cleared = 3;
  static const int info = 4;
}

/// DeviceEvent tags (key 1 of the Event map).
abstract final class EventTag {
  static const int reportPressed = 0;
  static const int reportSubmitted = 1;
  static const int confirmResponse = 2;
  static const int settingsPhoneConnect = 3;
  static const int settingsSoundToggle = 4;
  static const int settingsThemeChanged = 5;
  static const int settingsUnitChanged = 6;
  static const int settingsFilterChanged = 7;
  static const int heartbeat = 8;
}

/// UiConfig bit positions (set = feature ON; all-on == factory state).
abstract final class UiBit {
  static const int meldenPage = 0;
  static const int settingsPage = 1;
  static const int hazardOverlay = 2;
  static const int confirmOverlay = 3;
  static const int signColumns = 4;
  static const int directionArrows = 5;
  static const int peerCount = 6;
  static const int gearButton = 7;
  static const int connectQr = 8;
  static const int bootAnimation = 9;
  static const int count = 10;
}

/// Sign columns: the wire carries up to [signListMax] codes per column, the display
/// shows the newest [signsDisplayed].
const int signListMax = 4;
const int signsDisplayed = 3;
