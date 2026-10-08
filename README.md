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
- On the first install, MiPushCut hides the stock XMSF only when
  `/product/app/split-XiaomiServiceFrameworkCN` exists and contains an APK
- The stock XMSF replacement is an empty `.replace` directory; install the
  MiPushFramework `com.xiaomi.xmsf` APK normally after reboot rather than
  copying it into `/product`
- Updates keep the previous MiPushCut decision in
  `/data/adb/mipush_zygisk/mipushcut.state`, so a temporarily hidden stock path
  does not disable an already active replacement
- The first update from a pre-state release migrates the decision from its
  existing module `.replace` marker before the old module directory is replaced
- On KernelSU, an active metamodule is required for MiPushCut. If stock XMSF is
  detected without one, installation stops with instructions to install
  `meta-overlayfs` (or another compatible metamodule) and retry

### Install modes (volume keys)

The installer asks for a mode with volume keys (Vol+ selects the highlighted
option, Vol- cycles, 10s timeout takes the default):

- **cut + spoof** (default) — hide stock XMSF and spoof device props
- **cut only** — hide stock XMSF; `spoof=off` is written to app.conf and the
  zygisk module keeps only the XMSF marker prop
- **spoof only** — device spoofing with stock XMSF untouched

The default mirrors the previous install's persisted decisions.

### Shared-uid safety gate

On ROMs where SystemUI runs inside the android.uid.system (uid 1000) shared
user with stock XMSF (older MIUI/HyperOS ports), hiding the platform-signed
stock package can flip the shared user's seinfo base to "default" — that
seinfo has no seapp_contexts ":complete" entry and zygote aborts every
SystemUI fork. The installer detects this coupling and requires explicit
consent before enabling MiPushCut; unattended installs skip MiPushCut.

### Boot self-heal

When MiPushCut is enabled, `service.sh` samples SystemUI's persisted seinfo
after boot. If the base flipped to "default", MiPushCut is auto-disabled in
`mipushcut.state` and a notification is posted; the next boot recovers.

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
Package rules are syntax-based: explicitly configured vendor and system packages such as
`com.xiaomi.smarthome` and `com.android.settings` are accepted. Only the exact `android` package
and malformed package names are ignored.

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

The ABI-specific and universal zips are written under `build/`. CI builds the ARM and x86 ABI
groups on matching runner architectures before creating the universal package.

To reproduce the split CI build manually, build each native runner group without a universal ZIP:

```bash
MIPUSH_ZYGISK_BUILD_ABIS="arm64-v8a armeabi-v7a" MIPUSH_ZYGISK_PACKAGE_UNIVERSAL=false ./build.sh
MIPUSH_ZYGISK_BUILD_ABIS="x86 x86_64" MIPUSH_ZYGISK_PACKAGE_UNIVERSAL=false ./build.sh
```

After collecting all four libraries under `magisk/zygisk/`, package them without rebuilding:

```bash
MIPUSH_ZYGISK_SKIP_BUILD=true MIPUSH_ZYGISK_PACKAGE_UNIVERSAL=true ./build.sh
```

## Install

1. Build or download the module zip
2. Open Magisk app
3. Go to Modules → Install from storage
4. Select the zip file
5. Reboot

If MiPushCut was enabled, install the MiPushFramework APK after reboot so the
normal `/data/app` package becomes the visible `com.xiaomi.xmsf` implementation.
On systems without the stock XMSF path, the module keeps Zygisk support enabled
but skips the system replacement. KernelSU installation cannot safely fetch or
install a metamodule from inside this module transaction, so the prerequisite
must be installed separately first.

## Acknowledgements

Thanks to these projects for the ideas and implementation references:

- [fei-ke/HmsPushZygisk](https://github.com/fei-ke/HmsPushZygisk), for the compact Zygisk module shape and Build/SystemProperties spoofing flow.
- [Seyud/device_faker](https://github.com/Seyud/device_faker), for the per-app device spoofing model.
- [zygisk-api-rs](https://github.com/rmnscnce/zygisk-api-rs), for the Rust Zygisk API bindings.

## License

GPL-3.0-only.
