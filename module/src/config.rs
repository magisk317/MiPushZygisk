use std::fs;
use std::sync::OnceLock;

pub const CONFIG_PATH: &str = "/data/adb/mipush_zygisk/app.conf";

pub const DEVICE_CONFIG_PATH: &str = "/data/adb/mipush_zygisk/device.conf";

pub const XMSF_PACKAGE_NAME: &str = "com.xiaomi.xmsf";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Profile {
    Miui14,
    Os4,
}

pub fn profile() -> Profile {
    let content = fs::read_to_string(CONFIG_PATH).unwrap_or_default();
    content
        .lines()
        .find_map(|line| {
            let value = line.trim().strip_prefix("profile=")?.trim();
            Some(match value {
                "os4" => Profile::Os4,
                _ => Profile::Miui14,
            })
        })
        .unwrap_or(Profile::Miui14)
}

pub fn observe_enabled() -> bool {
    fs::read_to_string(CONFIG_PATH)
        .ok()
        .and_then(|content| {
            content
                .lines()
                .find_map(|line| line.trim().strip_prefix("observe=")?.parse().ok())
        })
        .unwrap_or(false)
}

#[derive(Clone, Copy)]
pub struct SpoofProps<'a> {
    pub system_properties: &'a [(&'a str, &'a str)],
    pub build_properties: &'a [(&'a str, &'a str)],
    pub build_version_properties: &'a [(&'a str, &'a str)],
}

pub const DEFAULT_SPOOF_PROPS: SpoofProps<'static> = SpoofProps {
    system_properties: &[
        ("ro.build.hw_emui_api_level", ""),
        ("ro.build.version.emui", ""),
        ("ro.vendor.build.emui", ""),
        ("ro.huawei.build.display.id", ""),
        ("ro.build.flyme.version", ""),
        ("ro.flyme.version.id", ""),
        ("ro.build.meizu.rom", ""),
        ("ro.build.version.opporom", ""),
        ("ro.build.version.oplusrom", ""),
        ("ro.coloros.version", ""),
        ("ro.vivo.os.name", ""),
        ("ro.vivo.os.version", ""),
        ("ro.funtouch.version", ""),
        ("ro.oneplus.version", ""),
        ("ro.oxygen.version", ""),
        ("ro.samsung.smd.version", ""),
        ("ro.build.scafe.version", ""),
        ("persist.sys.oppo.region", ""),
        ("ro.oppo.regionmark", ""),
        ("ro.hw.country", ""),
        ("ro.csc.countryiso_code", ""),
        ("gsm.vivo.countrycode", ""),
        ("persist.sys.oem.region", ""),
        ("ro.product.brand", "Xiaomi"),
        ("ro.product.manufacturer", "Xiaomi"),
        ("ro.product.model", "Redmi K30 5G"),
        ("ro.product.device", "picasso"),
        ("ro.product.name", "picasso"),
        ("ro.product.board", "picasso"),
        ("ro.product.cpu.abi", "arm64-v8a"),
        ("ro.product.cpu.abi2", "armeabi-v7a"),
        ("ro.product.cpu.abilist", "arm64-v8a,armeabi-v7a,armeabi"),
        ("ro.product.cpu.abilist32", "armeabi-v7a,armeabi"),
        ("ro.product.cpu.abilist64", "arm64-v8a"),
        ("ro.miui.ui.version.name", "V130"),
        ("ro.miui.ui.version.code", "13"),
        ("ro.miui.version.code_time", "1625587200"),
        ("ro.miui.build.region", "cn"),
        ("ro.miui.internal.storage", "/sdcard/"),
        ("ro.miui.cust_device", "picasso"),
        ("ro.miui.cust_variant", "cn"),
        ("ro.product.mod_device", "picasso"),
        ("ro.miui.has_gmscore", "1"),
        ("ro.miui.notch", "1"),
        ("ro.miui.has_security_keyboard", "1"),
        ("ro.fota.oem", "Xiaomi"),
        ("ro.rom.zone", "1"),
        ("ro.mi.development", "false"),
        ("ro.build.display.id", "SKQ1.211006.001 test-keys"),
        ("ro.build.id", "SKQ1.211006.001"),
        ("ro.build.version.incremental", "V13.0.5.0.SGICNXM"),
        ("ro.build.version.release", "12"),
        ("ro.build.version.security_patch", "2022-02-01"),
        ("ro.build.type", "user"),
        ("ro.build.user", "builder"),
        ("ro.build.host", "miui-build"),
        ("ro.build.tags", "release-keys"),
        (
            "ro.build.description",
            "picasso-user 12 SKQ1.211006.001 V13.0.5.0.SGICNXM release-keys",
        ),
        ("ro.build.product", "picasso"),
        (
            "ro.product.property_source_order",
            "odm,vendor,product,system_ext,system",
        ),
        ("ro.product.system.manufacturer", "Xiaomi"),
        ("ro.product.vendor.brand", "Xiaomi"),
        ("ro.product.vendor.manufacturer", "Xiaomi"),
        ("ro.miui.region", "CN"),
        ("ro.vendor.miui.region", "CN"),
        ("ro.product.locale", "zh-CN"),
        ("ro.product.locale.region", "CN"),
        ("ro.product.locale.language", "zh"),
        ("ro.product.country.region", "CN"),
        ("persist.sys.country", "CN"),
        ("persist.sys.miconnect.running", "1"),
        ("persist.sys.millet.handshake", "true"),
        ("persist.sys.brightmillet.enable", "true"),
        ("ro.miui.enable_cloud_verify", "true"),
        ("ro.vendor.radio.build_region", "cn"),
        ("ro.vendor.radio.build_profile", "miui"),
        ("sys.boot_completed", "1"),
    ],
    build_properties: &[
        ("BOARD", "picasso"),
        ("BRAND", "Xiaomi"),
        ("MANUFACTURER", "Xiaomi"),
        ("MODEL", "Redmi K30 5G"),
        ("DEVICE", "picasso"),
        ("PRODUCT", "picasso"),
        ("DISPLAY", "SKQ1.211006.001 test-keys"),
        ("CPU_ABI", "arm64-v8a"),
        ("CPU_ABI2", "armeabi-v7a"),
        (
            "FINGERPRINT",
            "Redmi/picasso/picasso:12/SKQ1.211006.001/V13.0.5.0.SGICNXM:user/release-keys",
        ),
        ("HOST", "miui-build"),
        ("ID", "SKQ1.211006.001"),
        ("TAGS", "release-keys"),
        ("TYPE", "user"),
        ("USER", "builder"),
    ],
    build_version_properties: &[
        ("INCREMENTAL", "V13.0.5.0.SGICNXM"),
        ("RELEASE", "12"),
        ("SECURITY_PATCH", "2022-02-01"),
    ],
};

struct PackageProps<'a> {
    package_name: &'a str,
    system_properties: &'a [(&'a str, &'a str)],
    build_properties: &'a [(&'a str, &'a str)],
    build_version_properties: &'a [(&'a str, &'a str)],
}

const PACKAGE_PROPS: &[PackageProps] = &[PackageProps {
    package_name: XMSF_PACKAGE_NAME,
    system_properties: &[("mipush.zygisk.enabled", "true")],
    build_properties: &[],
    build_version_properties: &[],
}];

/// A group of `key=value` device properties parsed from device.conf, owned so
/// it can outlive the file read. Split to mirror the three spoof categories.
#[derive(Default)]
struct PropSet {
    system: Vec<(String, String)>,
    build: Vec<(String, String)>,
    build_version: Vec<(String, String)>,
}

impl PropSet {
    fn is_empty(&self) -> bool {
        self.system.is_empty() && self.build.is_empty() && self.build_version.is_empty()
    }
}

/// Parsed device.conf: explicit overrides on top of the selected profile plus
/// optional per-package patches.
struct DeviceConfig {
    global: PropSet,
    packages: Vec<(String, PropSet)>,
}

impl DeviceConfig {
    fn is_empty(&self) -> bool {
        self.global.is_empty() && self.packages.iter().all(|(_, set)| set.is_empty())
    }
}

/// Which `[section]` the parser is currently filling.
enum Section {
    Skip,
    GlobalSystem,
    GlobalBuild,
    GlobalBuildVersion,
    PackageSystem(usize),
    PackageBuild(usize),
    PackageBuildVersion(usize),
}

/// Load and cache device.conf. Returns `None` when the file is missing,
/// unreadable, or yields no usable properties so callers fall back to
/// the selected profile. Parsed once per process; cached for later hooks.
fn device_config() -> Option<&'static DeviceConfig> {
    static CONFIG: OnceLock<Option<DeviceConfig>> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let content = fs::read_to_string(DEVICE_CONFIG_PATH).ok()?;
            let parsed = parse_device_config(&content);
            if parsed.is_empty() {
                None
            } else {
                Some(parsed)
            }
        })
        .as_ref()
}

fn parse_device_config(content: &str) -> DeviceConfig {
    let mut config = DeviceConfig {
        global: PropSet::default(),
        packages: Vec::new(),
    };
    let mut section = Section::Skip;

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        if let Some(header) = line.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            section = resolve_section(header.trim(), &mut config);
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        if key.is_empty() {
            continue;
        }

        let target = match section {
            Section::Skip => continue,
            Section::GlobalSystem => &mut config.global.system,
            Section::GlobalBuild => &mut config.global.build,
            Section::GlobalBuildVersion => &mut config.global.build_version,
            Section::PackageSystem(idx) => &mut config.packages[idx].1.system,
            Section::PackageBuild(idx) => &mut config.packages[idx].1.build,
            Section::PackageBuildVersion(idx) => &mut config.packages[idx].1.build_version,
        };
        upsert(target, key, value);
    }

    config
}

/// Map a `[header]` to the section it selects, creating a package entry when
/// the header uses the `pkg:section` form. Unknown headers are skipped.
fn resolve_section(header: &str, config: &mut DeviceConfig) -> Section {
    match header {
        "system" => return Section::GlobalSystem,
        "build" => return Section::GlobalBuild,
        "build.version" => return Section::GlobalBuildVersion,
        _ => {}
    }

    let Some((pkg, sub)) = header.rsplit_once(':') else {
        return Section::Skip;
    };
    let pkg = pkg.trim();
    if pkg.is_empty() {
        return Section::Skip;
    }
    let idx = package_index(config, pkg);
    match sub.trim() {
        "system" => Section::PackageSystem(idx),
        "build" => Section::PackageBuild(idx),
        "build.version" => Section::PackageBuildVersion(idx),
        _ => Section::Skip,
    }
}

fn package_index(config: &mut DeviceConfig, pkg: &str) -> usize {
    if let Some(idx) = config.packages.iter().position(|(name, _)| name == pkg) {
        idx
    } else {
        config.packages.push((pkg.to_owned(), PropSet::default()));
        config.packages.len() - 1
    }
}

/// Insert or replace a key, so later lines override earlier ones in a section.
fn upsert(target: &mut Vec<(String, String)>, key: &str, value: &str) {
    if let Some(slot) = target.iter_mut().find(|(k, _)| k == key) {
        slot.1 = value.to_owned();
    } else {
        target.push((key.to_owned(), value.to_owned()));
    }
}

/// Merge a global section with an optional per-package patch (patch keys win,
/// global keys are inherited) and leak the result to `'static`. The leak is
/// bounded: `get_properties_for_package` runs once per app process.
fn merge_section(
    base: &'static [(&'static str, &'static str)],
    global: &'static [(String, String)],
    patch: Option<&'static [(String, String)]>,
) -> &'static [(&'static str, &'static str)] {
    let mut out = base.to_vec();
    for overrides in [Some(global), patch] {
        if let Some(overrides) = overrides {
            for (k, v) in overrides {
                if let Some(slot) = out.iter_mut().find(|(ek, _)| *ek == k.as_str()) {
                    slot.1 = v.as_str();
                } else {
                    out.push((k.as_str(), v.as_str()));
                }
            }
        }
    }
    Box::leak(out.into_boxed_slice())
}

pub fn get_properties_for_package(pkg: &str) -> SpoofProps<'static> {
    if let Some(entry) = PACKAGE_PROPS.iter().find(|p| p.package_name == pkg) {
        return SpoofProps {
            system_properties: entry.system_properties,
            build_properties: entry.build_properties,
            build_version_properties: entry.build_version_properties,
        };
    }

    let base = profile_defaults(profile());
    let Some(config) = device_config() else {
        return base;
    };

    let patch = config
        .packages
        .iter()
        .find(|(name, _)| name == pkg)
        .map(|(_, set)| set);

    SpoofProps {
        system_properties: merge_section(
            base.system_properties,
            &config.global.system,
            patch.map(|p| p.system.as_slice()),
        ),
        build_properties: merge_section(
            base.build_properties,
            &config.global.build,
            patch.map(|p| p.build.as_slice()),
        ),
        build_version_properties: merge_section(
            base.build_version_properties,
            &config.global.build_version,
            patch.map(|p| p.build_version.as_slice()),
        ),
    }
}

fn profile_defaults(profile: Profile) -> SpoofProps<'static> {
    if profile == Profile::Miui14 {
        return DEFAULT_SPOOF_PROPS;
    }
    let mut system = DEFAULT_SPOOF_PROPS.system_properties.to_vec();
    let mut build = DEFAULT_SPOOF_PROPS.build_properties.to_vec();
    let mut version = DEFAULT_SPOOF_PROPS.build_version_properties.to_vec();
    let set = |items: &mut Vec<(&'static str, &'static str)>, key, value| {
        if let Some(item) = items.iter_mut().find(|(name, _)| *name == key) {
            item.1 = value;
        } else {
            items.push((key, value));
        }
    };
    match profile {
        Profile::Os4 => {
            set(&mut system, "ro.product.model", "25113PN0EC");
            set(&mut system, "ro.product.device", "pudding");
            set(&mut system, "ro.product.name", "pudding");
            set(&mut system, "ro.product.board", "canoe");
            set(&mut system, "ro.product.marketname", "Xiaomi 17");
            set(&mut system, "ro.product.cpu.abi2", "");
            set(&mut system, "ro.product.cpu.abilist", "arm64-v8a");
            set(&mut system, "ro.product.cpu.abilist32", "");
            set(&mut system, "ro.miui.ui.version.name", "V816");
            set(&mut system, "ro.miui.ui.version.code", "816");
            set(&mut system, "ro.miui.version.code_time", "");
            set(&mut system, "ro.miui.cust_device", "pudding");
            set(&mut system, "ro.miui.cust_variant", "cn_chinatelecom");
            set(&mut system, "ro.miui.cust_hardware", "V1");
            set(&mut system, "ro.product.mod_device", "pudding");
            set(&mut system, "ro.build.display.id", "CP2A.260605.016");
            set(&mut system, "ro.build.id", "CP2A.260605.016");
            set(
                &mut system,
                "ro.build.version.incremental",
                "OS4.0.0.9.XPCCNXM",
            );
            set(&mut system, "ro.build.version.release", "17");
            set(&mut system, "ro.build.version.sdk", "37");
            set(&mut system, "ro.build.version.security_patch", "2026-08-01");
            set(
                &mut system,
                "ro.build.description",
                "pudding-user 17 CP2A.260605.016 OS4.0.0.9.XPCCNXM release-keys",
            );
            set(&mut system, "ro.build.product", "pudding");
            set(
                &mut system,
                "ro.build.fingerprint",
                "Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.9.XPCCNXM:user/release-keys",
            );
            set(&mut build, "BOARD", "canoe");
            set(&mut build, "MODEL", "25113PN0EC");
            set(&mut build, "DEVICE", "pudding");
            set(&mut build, "PRODUCT", "pudding");
            set(&mut build, "DISPLAY", "CP2A.260605.016");
            set(&mut build, "CPU_ABI2", "");
            set(
                &mut build,
                "FINGERPRINT",
                "Xiaomi/pudding/pudding:17/CP2A.260605.016/OS4.0.0.9.XPCCNXM:user/release-keys",
            );
            set(&mut build, "ID", "CP2A.260605.016");
            set(&mut version, "INCREMENTAL", "OS4.0.0.9.XPCCNXM");
            set(&mut version, "RELEASE", "17");
            set(&mut version, "SDK", "37");
            set(&mut version, "SECURITY_PATCH", "2026-08-01");
        }
        Profile::Miui14 => unreachable!(),
    }
    SpoofProps {
        system_properties: Box::leak(system.into_boxed_slice()),
        build_properties: Box::leak(build.into_boxed_slice()),
        build_version_properties: Box::leak(version.into_boxed_slice()),
    }
}

pub fn is_managed_package(package_name: &str) -> bool {
    let package_name = package_name.trim();
    // Package filtering is an explicit caller policy. Native Zygisk only
    // validates the identity syntax so Xiaomi and other vendor packages remain
    // configurable when the user intentionally includes them.
    package_name != "android" && is_android_package_name(package_name)
}

pub fn is_valid_process_name(package_name: &str, process_name: &str) -> bool {
    let process_name = process_name.trim();
    if process_name == package_name {
        return true;
    }
    process_name
        .strip_prefix(package_name)
        .and_then(|suffix| suffix.strip_prefix(':'))
        .is_some_and(is_process_suffix)
}

fn is_android_package_name(value: &str) -> bool {
    let mut parts = value.split('.');
    let Some(first) = parts.next() else {
        return false;
    };
    if !is_package_head(first) {
        return false;
    }
    let mut has_suffix = false;
    for part in parts {
        has_suffix = true;
        if part.is_empty() || !part.bytes().all(is_package_char) {
            return false;
        }
    }
    has_suffix
}

fn is_package_head(value: &str) -> bool {
    let mut bytes = value.bytes();
    matches!(bytes.next(), Some(b'a'..=b'z' | b'A'..=b'Z')) && bytes.all(is_package_char)
}

fn is_package_char(value: u8) -> bool {
    matches!(value, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_')
}

fn is_process_suffix(value: &str) -> bool {
    !value.is_empty()
        && value
            .bytes()
            .all(|byte| is_package_char(byte) || matches!(byte, b'.' | b'-'))
}

#[cfg(test)]
mod tests {
    use super::{is_managed_package, is_valid_process_name, parse_device_config};

    fn find<'a>(props: &'a [(String, String)], key: &str) -> Option<&'a str> {
        props
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    #[test]
    fn parses_global_sections_by_category() {
        let config = parse_device_config(
            "\
[system]
ro.product.model=Redmi K30 5G
ro.product.brand=Xiaomi
[build]
MODEL=Redmi K30 5G
[build.version]
RELEASE=12
",
        );
        assert_eq!(
            find(&config.global.system, "ro.product.model"),
            Some("Redmi K30 5G")
        );
        assert_eq!(
            find(&config.global.system, "ro.product.brand"),
            Some("Xiaomi")
        );
        assert_eq!(find(&config.global.build, "MODEL"), Some("Redmi K30 5G"));
        assert_eq!(find(&config.global.build_version, "RELEASE"), Some("12"));
        assert!(config.packages.is_empty());
    }

    #[test]
    fn parses_per_package_patch_sections() {
        let config = parse_device_config(
            "\
[system]
ro.product.model=Redmi K30 5G
[com.example.app:system]
ro.product.model=Pixel 8
[com.example.app:build]
MODEL=Pixel 8
",
        );
        assert_eq!(config.packages.len(), 1);
        let (name, set) = &config.packages[0];
        assert_eq!(name, "com.example.app");
        assert_eq!(find(&set.system, "ro.product.model"), Some("Pixel 8"));
        assert_eq!(find(&set.build, "MODEL"), Some("Pixel 8"));
        // global stays untouched by the patch
        assert_eq!(
            find(&config.global.system, "ro.product.model"),
            Some("Redmi K30 5G")
        );
    }

    #[test]
    fn ignores_comments_blank_lines_and_unknown_sections() {
        let config = parse_device_config(
            "\
# a comment

[bogus]
ignored=1
[system]
ro.product.model=Redmi K30 5G
malformed line without equals
=novalue
",
        );
        assert_eq!(
            find(&config.global.system, "ro.product.model"),
            Some("Redmi K30 5G")
        );
        assert_eq!(config.global.system.len(), 1);
        assert!(config.global.build.is_empty());
    }

    #[test]
    fn later_duplicate_keys_override_earlier_ones() {
        let config = parse_device_config(
            "\
[system]
ro.product.model=First
ro.product.model=Second
",
        );
        assert_eq!(
            find(&config.global.system, "ro.product.model"),
            Some("Second")
        );
        assert_eq!(config.global.system.len(), 1);
    }

    #[test]
    fn empty_content_yields_empty_config() {
        let config = parse_device_config("# only comments\n\n");
        assert!(config.is_empty());
    }

    #[test]
    fn validates_package_identity_without_vendor_blacklist() {
        assert!(!is_managed_package("android"));
        assert!(is_managed_package("com.android.settings"));
        assert!(is_managed_package("com.miui.securitycenter"));
        assert!(is_managed_package("com.xiaomi.smarthome"));
        assert!(is_managed_package("com.mipay.wallet"));
        assert!(is_managed_package("com.example.app"));
    }

    #[test]
    fn validates_process_names_for_package() {
        assert!(is_valid_process_name("com.example.app", "com.example.app"));
        assert!(is_valid_process_name(
            "com.example.app",
            "com.example.app:push"
        ));
        assert!(!is_valid_process_name(
            "com.example.app",
            "com.other.app:push"
        ));
    }
}
