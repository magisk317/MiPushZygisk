pub const CONFIG_PATH: &str = "/data/adb/mipush_zygisk/app.conf";

pub const XMSF_PACKAGE_NAME: &str = "com.xiaomi.xmsf";

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

pub fn get_properties_for_package(pkg: &str) -> SpoofProps<'static> {
    if let Some(entry) = PACKAGE_PROPS.iter().find(|p| p.package_name == pkg) {
        SpoofProps {
            system_properties: entry.system_properties,
            build_properties: entry.build_properties,
            build_version_properties: entry.build_version_properties,
        }
    } else {
        DEFAULT_SPOOF_PROPS
    }
}

pub fn is_managed_package(package_name: &str) -> bool {
    let package_name = package_name.trim();
    if package_name == "android" || !is_android_package_name(package_name) {
        return false;
    }
    let denied_prefixes = [
        "android.",
        "com.android.",
        "com.google.android.",
        "com.mi.",
        "com.miui.",
        "com.milink.",
        "com.mipay.",
        "com.xiaomi.",
        "miui.",
    ];
    !denied_prefixes
        .iter()
        .any(|prefix| package_name.starts_with(prefix))
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
    use super::{is_managed_package, is_valid_process_name};

    #[test]
    fn rejects_system_and_xiaomi_family_packages() {
        assert!(!is_managed_package("android"));
        assert!(!is_managed_package("com.android.settings"));
        assert!(!is_managed_package("com.miui.securitycenter"));
        assert!(!is_managed_package("com.xiaomi.smarthome"));
        assert!(!is_managed_package("com.mipay.wallet"));
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
