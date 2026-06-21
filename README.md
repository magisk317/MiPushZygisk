# MiPush Zygisk

A Magisk/Zygisk module that spoofs Xiaomi/MIUI device properties for selected app processes before app startup.

This module is designed to work with [MiPushFramework](https://github.com/magisk317/MiPushFramework), providing stealthy device spoofing at the native/Zygisk level that bypasses Xposed detection.

## Features

- Spoofs `android.os.Build` fields and `SystemProperties` native getters to simulate a Xiaomi device
- Per-app configuration via a simple text config file
- Companion process for efficient config reads
- Sets `mipush.zygisk.enabled=true` system property for MiPushFramework detection
- Supports arm64-v8a, armeabi-v7a, x86, x86_64

## How It Works

The module hooks into Zygote and, before each app process starts:

1. Queries the companion process to check if the app is in the config
2. If yes, modifies `android.os.Build` fields (BRAND, MANUFACTURER, MODEL, etc.)
3. Replaces `SystemProperties` native getters to return spoofed values for Xiaomi properties

This is more stealthy than Xposed-based spoofing because some apps detect Xposed hooking environments.

## Integration with MiPushFramework

When installed alongside MiPushFramework:

- The module sets `mipush.zygisk.enabled=true` system property
- MiPushFramework can detect this property to show Zygisk status in its UI
- The config file at `/data/adb/mipush_zygisk/app.conf` controls which apps get spoofed

## Config

Create or edit:

```text
/data/adb/mipush_zygisk/app.conf
```

Supported lines:

```text
# all processes of a package
com.example.app

# only one process
com.example.app|com.example.app:push
```

Blank lines and lines starting with `#` are ignored.
System packages and Xiaomi-family packages are ignored so this config matches MiPushFramework's managed-app model.

A default config is provided with common apps that use MiPush.

## Build

Requirements:

- Android NDK
- Rust/Cargo with Android targets installed
- `zip`

Build:

```bash
./build.sh
```

The zip is written under `build/`.

## Install

1. Build or download the module zip
2. Open Magisk app
3. Go to Modules → Install from storage
4. Select the zip file
5. Reboot

## Acknowledgements

Thanks to these projects for the ideas and implementation references:

- [fei-ke/HmsPushZygisk](https://github.com/fei-ke/HmsPushZygisk), for the compact Zygisk module shape and Build/SystemProperties spoofing flow.
- [Seyud/device_faker](https://github.com/Seyud/device_faker), for the per-app device spoofing model.
- [zygisk-api-rs](https://github.com/rmnscnce/zygisk-api-rs), for the Rust Zygisk API bindings.

## License

GPL-3.0-only.
