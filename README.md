# TASCAM US-2x2 / US-4x4 Control — native Apple silicon

A native arm64 replacement for the **TASCAM US-2x2 / US-4x4 Settings Panel**
(the x86_64 Qt 5 application from the 2016 installer). It controls the
interface's internal routing over USB and does not depend on Rosetta 2,
Qt, or any third-party library.

![Screenshot](native/docs/screenshot.png)

## Why this exists

The original panel is an `x86_64` Qt 5 app. It also talks to the device
through Apple's legacy `IOUSBDeviceInterface` user-client plug-in
(`IOUSBDeviceLib.plugin`), which is no longer present on current macOS
releases — so even under Rosetta it is living on borrowed time.

This replacement is written in Swift, uses the modern `IOUSBHost` API, and
builds as a thin **arm64** binary.

## Features

- Direct monitor mode (Mono / Stereo) per input pair
- Audio input enable/disable per channel
- Line output routing per output pair
  (Monitor Mix / Computer Out 1-2 / Computer Out 3-4)
- Auto Power Save
- Live firmware version, model, and current sample rate
- Automatic connect/disconnect detection (1 s polling, same as the original)
- Model-aware UI: US-2x2 gets 2 inputs / 1 output pair, US-4x4 gets 4 inputs / 2 pairs

## Requirements

- Apple silicon Mac
- macOS 13 Ventura or newer
- TASCAM US-2x2 or US-4x4 connected by USB

## Build

```sh
cd native
./build.sh
```

The result is `build/TASCAM US Control.app` (arm64, ad-hoc signed).

Universal build (optional):

```sh
ARCHS="arm64 x86_64" ./build.sh
```

There are no external dependencies; only the macOS SDK is required.

## Install

Drag `TASCAM US Control.app` to `/Applications`. Because the build is ad-hoc
signed (not notarized), macOS may require **right-click → Open** the first
time, or you can clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/TASCAM US Control.app"
```

## How it was reverse engineered

1. The installer was expanded with `pkgutil --expand-full`. Its payload is a
   single Qt 5 app. The main binary is unstripped and contains full C++
   symbols, which exposed the protocol layer:
   - `QUSDevice` — high-level get/set operations
   - `QUSDeviceUnit` — request dispatch and IOKit plumbing
   - `usbdevs_*` / `usctl_*` — a small statically linked USB helper library
     (`../../ustest/usbdevs.c`)
2. Disassembly of `usbdevs_dev_vendor_request_in/out` showed standard
   `IOUSBDeviceInterface::DeviceRequest` control transfers on endpoint 0.
3. Disassembly of the `QUSDevice` methods and the request dispatch table
   produced the request map below.
4. The sample rate is read by parsing the USB configuration descriptor for
   the UAC2 clock-source descriptor and issuing a standard
   `GET_CUR(SAMPLING_FREQUENCY_CONTROL)` class request.

### USB identity

| Model  | Vendor ID | Product ID |
|--------|-----------|------------|
| US-2x2 | `0x0644`  | `0x8045`   |
| US-4x4 | `0x0644`  | `0x804E`   |

### Vendor request map

All are device-recipient control requests on endpoint 0.
`IN` uses `bmRequestType 0xC0`, `OUT` uses `bmRequestType 0x40`.

| bRequest | Meaning | wValue | wIndex | wLength |
|----------|---------|--------|--------|---------|
| `0x01` | Get firmware version | — | — | 2 |
| `0x03` | Get auto power save | — | — | 1 |
| `0x05` | Get audio input on/off | — | channel | 1 |
| `0x07` | Get direct monitor mode | — | input pair | 1 |
| `0x09` | Get line output routing | — | output pair | 1 |
| `0x04` | Set auto power save | 0/1 | — | 0 |
| `0x06` | Set audio input on/off | 0/1 | channel | 0 |
| `0x08` | Set direct monitor mode | 0=mono, 1=stereo | input pair | 0 |
| `0x0A` | Set line output routing | 0=mix, 1=out 1-2, 2=out 3-4 | output pair | 0 |

The firmware response is two BCD bytes: `0x01 0x01` → `1.01`.

### Sample rate

- Find the class-specific interface descriptor (`0x24`, subtype `0x0A`,
  clock source) inside the audio-control interface (class 1, subclass 1,
  protocol `0x20`).
- `wIndex = (bClockID << 8) | bInterfaceNumber`
- `bmRequestType 0xA1`, `bRequest 0x01` (`GET_CUR`),
  `wValue 0x0100` (`SAMPLING_FREQUENCY_CONTROL`), 4-byte little-endian Hz.

## Verification

Tested on a real **US-4x4**, firmware **1.01**, macOS **26.6.2** (Apple
silicon):

- All getters returned plausible values (`inputs on`, direct monitor
  stereo, line outputs 0/1, 48 kHz).
- Every setter was exercised, read back to confirm the change, and then
  restored to its original value:
  - auto power save
  - audio input 1
  - direct monitor 1-2
  - line output 1 and 2

The US-2x2 path uses the same protocol and model mapping as the original
app; its UI variant was verified with a debug-only demo state, but it has
not been tested against physical US-2x2 hardware here.

## Source layout

```
tascam-ui/
├── README.md
├── .gitignore
├── x86-app/                      # original vendor installer (not committed)
└── native/
    ├── build.sh
    ├── Sources/
    │   ├── TascamUS.swift            # USB discovery + protocol
    │   ├── DeviceModel.swift         # polling and observable state
    │   ├── ContentView.swift         # SwiftUI interface
    │   ├── TascamUSControlApp.swift  # app entry point
    │   └── Info.plist
    ├── Resources/AppIcon.icns        # icon from the original app
    └── docs/screenshot.png
```

## Notes and limitations

- The original app's online firmware/software update check is intentionally
  not included. It is unrelated to device control and those endpoints are
  long-lived web services.
- Only USB connected devices are supported, just like the original.
- While the panel is running it holds the USB control interface, so only one
  control application can use the device at a time. Audio streaming through
  CoreAudio is not affected.
- The app is not sandboxed, so no USB entitlement is required. If you
  re-sign it with a Developer ID, keep it un-sandboxed or add
  `com.apple.security.device.usb`.
- TASCAM and US-2x2/US-4x4 are trademarks of TEAC Corporation. This is an
  independent interoperability project, not affiliated with TEAC/TASCAM.
