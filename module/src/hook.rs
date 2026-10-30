use std::{
    collections::HashSet,
    ffi::CStr,
    fs,
    os::raw::{c_char, c_int, c_void},
    ptr,
    sync::{Mutex, OnceLock},
};

use jni::{
    objects::{JClass, JObject, JString, JValue},
    signature::RuntimeFieldSignature,
    strings::{JNIStr, JNIString},
    sys::JNINativeMethod,
    Env, EnvUnowned,
};
use log::debug;
use zygisk_api::api::{ZygiskApi, V4};

fn with_env<T: Default>(
    raw: *mut jni::sys::JNIEnv,
    f: impl FnOnce(&mut Env<'_>) -> jni::errors::Result<T>,
) -> Option<T> {
    let mut env = unsafe { EnvUnowned::from_raw(raw) };
    Some(
        env.with_env_no_catch(f)
            .resolve::<jni::errors::LogErrorAndDefault>(),
    )
}

fn jstring_to_string(env: &mut EnvUnowned<'_>, raw: jni::sys::jstring) -> String {
    if raw.is_null() {
        return String::new();
    }
    with_env(env.as_raw(), |env| {
        let value = unsafe { JString::from_raw(env, raw) };
        let result = value.mutf8_chars(env)?.to_string();
        let _ = value.into_raw();
        Ok(result)
    })
    .unwrap_or_default()
}

fn new_string(env: &mut EnvUnowned<'_>, value: &str) -> Option<jni::sys::jstring> {
    with_env(env.as_raw(), |env| Ok(env.new_string(value)?.into_raw()))
}

type NativeGetFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jstring,
    jni::sys::jstring,
) -> jni::sys::jstring;
type NativeGetOneFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jstring,
) -> jni::sys::jstring;
type NativeFindFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jstring,
) -> jni::sys::jlong;
type NativeHandleGetFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jlong,
) -> jni::sys::jstring;
type NativeGetIntFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jstring,
    jni::sys::jint,
) -> jni::sys::jint;
type NativeGetLongFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jstring,
    jni::sys::jlong,
) -> jni::sys::jlong;
type NativeGetBooleanFn = unsafe extern "C" fn(
    *mut jni::sys::JNIEnv,
    jni::sys::jclass,
    jni::sys::jstring,
    jni::sys::jboolean,
) -> jni::sys::jboolean;

static ORIG_NATIVE_GET: OnceLock<NativeGetFn> = OnceLock::new();
static ORIG_NATIVE_GET_ONE: OnceLock<NativeGetOneFn> = OnceLock::new();
static ORIG_NATIVE_FIND: OnceLock<NativeFindFn> = OnceLock::new();
static ORIG_NATIVE_HANDLE_GET: OnceLock<NativeHandleGetFn> = OnceLock::new();
static ORIG_NATIVE_GET_INT: OnceLock<NativeGetIntFn> = OnceLock::new();
static ORIG_NATIVE_GET_LONG: OnceLock<NativeGetLongFn> = OnceLock::new();
static ORIG_NATIVE_GET_BOOLEAN: OnceLock<NativeGetBooleanFn> = OnceLock::new();
static SPOOFED_SYS_PROPS: OnceLock<&'static [(&'static str, &'static str)]> = OnceLock::new();
static OBSERVED_KEYS: OnceLock<Mutex<Vec<String>>> = OnceLock::new();
static HANDLES: OnceLock<Mutex<Vec<&'static str>>> = OnceLock::new();

type NativePropertyGetFn = unsafe extern "C" fn(*const c_char, *mut c_char) -> c_int;
type NativePropertyReadFn = unsafe extern "C" fn(*const c_void, *mut c_char, *mut c_char) -> c_int;

static ORIG_BIONIC_PROPERTY_GET: OnceLock<NativePropertyGetFn> = OnceLock::new();
static ORIG_BIONIC_PROPERTY_READ: OnceLock<NativePropertyReadFn> = OnceLock::new();

fn observe_key(key: &str) {
    if !crate::config::observe_enabled() {
        return;
    }
    let keys = OBSERVED_KEYS.get_or_init(|| Mutex::new(Vec::new()));
    let Ok(mut keys) = keys.lock() else {
        return;
    };
    if keys.iter().any(|item| item == key) {
        return;
    }
    if keys.len() < 256 {
        keys.push(key.to_owned());
    }
}

unsafe extern "C" fn my_native_get(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    key_j: jni::sys::jstring,
    def_j: jni::sys::jstring,
) -> jni::sys::jstring {
    let mut jni_env = unsafe { EnvUnowned::from_raw(env) };

    let key = jstring_to_string(&mut jni_env, key_j);

    if let Some(value) = spoofed_value(&key) {
        return new_string(&mut jni_env, value).unwrap_or(def_j);
    }

    match ORIG_NATIVE_GET.get() {
        Some(orig) => orig(env, clazz, key_j, def_j),
        None => def_j,
    }
}

unsafe extern "C" fn my_native_get_int(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    key_j: jni::sys::jstring,
    def_j: jni::sys::jint,
) -> jni::sys::jint {
    if let Some(value) = lookup_spoofed_value(env, key_j).and_then(parse_int) {
        return value;
    }
    match ORIG_NATIVE_GET_INT.get() {
        Some(orig) => orig(env, clazz, key_j, def_j),
        None => def_j,
    }
}

unsafe extern "C" fn my_native_get_long(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    key_j: jni::sys::jstring,
    def_j: jni::sys::jlong,
) -> jni::sys::jlong {
    if let Some(value) = lookup_spoofed_value(env, key_j).and_then(parse_long) {
        return value;
    }
    match ORIG_NATIVE_GET_LONG.get() {
        Some(orig) => orig(env, clazz, key_j, def_j),
        None => def_j,
    }
}

unsafe extern "C" fn my_native_get_boolean(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    key_j: jni::sys::jstring,
    def_j: jni::sys::jboolean,
) -> jni::sys::jboolean {
    if let Some(value) = lookup_spoofed_value(env, key_j).and_then(parse_bool) {
        return value as jni::sys::jboolean;
    }
    match ORIG_NATIVE_GET_BOOLEAN.get() {
        Some(orig) => orig(env, clazz, key_j, def_j),
        None => def_j,
    }
}

unsafe fn lookup_spoofed_value(
    env: *mut jni::sys::JNIEnv,
    key_j: jni::sys::jstring,
) -> Option<&'static str> {
    if key_j.is_null() {
        return None;
    }
    let mut jni_env = unsafe { EnvUnowned::from_raw(env) };
    let key = jstring_to_string(&mut jni_env, key_j);
    spoofed_value(&key)
}

fn spoofed_value(key: &str) -> Option<&'static str> {
    observe_key(key);
    SPOOFED_SYS_PROPS
        .get()
        .and_then(|props| props.iter().find(|(prop, _)| *prop == key))
        .map(|(_, value)| *value)
}

fn copy_property_value(value: &str, output: *mut c_char) -> c_int {
    if output.is_null() {
        return 0;
    }
    // Android's PROP_VALUE_MAX is 92. Keep the native replacement bounded even if a future
    // profile accidentally contains a longer value; the caller still receives a valid C string.
    let bytes = value.as_bytes();
    let length = bytes.len().min(91);
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr().cast::<c_char>(), output, length);
        *output.add(length) = 0;
    }
    length as c_int
}

unsafe extern "C" fn my_bionic_property_get(name: *const c_char, value: *mut c_char) -> c_int {
    if !name.is_null() {
        let key = unsafe { CStr::from_ptr(name) }.to_str().unwrap_or_default();
        if let Some(spoofed) = spoofed_value(key) {
            return copy_property_value(spoofed, value);
        }
    }
    ORIG_BIONIC_PROPERTY_GET
        .get()
        .map(|original| unsafe { original(name, value) })
        .unwrap_or(0)
}

unsafe extern "C" fn my_bionic_property_read(
    property: *const c_void,
    name: *mut c_char,
    value: *mut c_char,
) -> c_int {
    let result = ORIG_BIONIC_PROPERTY_READ
        .get()
        .map(|original| unsafe { original(property, name, value) })
        .unwrap_or(0);
    if result <= 0 || name.is_null() || value.is_null() {
        return result;
    }
    let key = unsafe { CStr::from_ptr(name) }.to_str().unwrap_or_default();
    if let Some(spoofed) = spoofed_value(key) {
        return copy_property_value(spoofed, value);
    }
    result
}

fn parse_mapping_device(value: &str) -> Option<libc::dev_t> {
    let (major, minor) = value.split_once(':')?;
    let major = u32::from_str_radix(major, 16).ok()?;
    let minor = u32::from_str_radix(minor, 16).ok()?;
    Some(libc::makedev(major, minor))
}

fn should_hook_mapping(perms: &str, path: &str) -> bool {
    perms.contains('x')
        && !path.starts_with('[')
        && (path.ends_with(".so") || path.contains(".so.") || path.ends_with(".apk"))
}

fn mapped_elf_ids() -> Vec<(libc::dev_t, libc::ino_t)> {
    let Ok(maps) = fs::read_to_string("/proc/self/maps") else {
        return Vec::new();
    };
    let mut ids = HashSet::new();
    for line in maps.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 6 || !should_hook_mapping(fields[1], fields[5]) {
            continue;
        }
        let Some(device) = parse_mapping_device(fields[3]) else {
            continue;
        };
        let Ok(inode) = fields[4].parse::<libc::ino_t>() else {
            continue;
        };
        if inode != 0 {
            ids.insert((device, inode));
        }
    }
    ids.into_iter().collect()
}

/// Cover native callers which bypass Java `SystemProperties.native_get*`.
///
/// This deliberately hooks only the platform property read APIs and only for the
/// per-process profile already selected by MiPushZygisk. It never fabricates identifiers
/// such as serial, IMEI, Android ID, advertising ID, MAC, account or registration tokens.
pub fn hook_native_system_properties(api: &mut ZygiskApi<'_, V4>) {
    let mappings = mapped_elf_ids();
    if mappings.is_empty() {
        debug!("native property hooks skipped: no executable ELF mappings");
        return;
    }

    let mut registered = 0usize;
    for (device, inode) in mappings {
        let mut original_get: *const () = ptr::null();
        let mut original_read: *const () = ptr::null();
        unsafe {
            api.plt_hook_register(
                device,
                inode,
                c"__system_property_get",
                my_bionic_property_get as *const (),
                &mut original_get,
            );
            api.plt_hook_register(
                device,
                inode,
                c"__system_property_read",
                my_bionic_property_read as *const (),
                &mut original_read,
            );
        }
        if !original_get.is_null() {
            let original: NativePropertyGetFn = unsafe { std::mem::transmute(original_get) };
            let _ = ORIG_BIONIC_PROPERTY_GET.set(original);
            registered += 1;
        }
        if !original_read.is_null() {
            let original: NativePropertyReadFn = unsafe { std::mem::transmute(original_read) };
            let _ = ORIG_BIONIC_PROPERTY_READ.set(original);
            registered += 1;
        }
    }

    match api.plt_hook_commit() {
        Ok(()) => debug!(
            "native property hooks committed mappings={} registrations={registered}",
            registered
        ),
        Err(error) => debug!("native property hook commit failed: {error:?}"),
    }
}

fn parse_int(value: &str) -> Option<jni::sys::jint> {
    value.trim().parse::<jni::sys::jint>().ok()
}

fn parse_long(value: &str) -> Option<jni::sys::jlong> {
    value.trim().parse::<jni::sys::jlong>().ok()
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "y" | "yes" | "on" => Some(true),
        "0" | "false" | "n" | "no" | "off" => Some(false),
        _ => None,
    }
}

pub fn hook_build(env: &mut Env<'_>, props: &[(&str, &str)], version_props: &[(&str, &str)]) {
    debug!("hook android.os.Build");

    let build_class_name = JNIString::new("android/os/Build");
    let build_class = match env.find_class(&build_class_name) {
        Ok(class) => class,
        Err(err) => {
            debug!("find android.os.Build failed: {err:?}");
            return;
        }
    };

    for (field, value) in props {
        set_static_string_field(env, &build_class, field, value);
    }

    if version_props.is_empty() {
        return;
    }
    let version_class_name = JNIString::new("android/os/Build$VERSION");
    let version_class = match env.find_class(&version_class_name) {
        Ok(class) => class,
        Err(err) => {
            debug!("find android.os.Build.VERSION failed: {err:?}");
            return;
        }
    };
    for (field, value) in version_props {
        set_static_string_field(env, &version_class, field, value);
    }
}

fn set_static_string_field(env: &mut Env<'_>, class: &JClass<'_>, field: &str, value: &str) {
    let value = match env.new_string(value) {
        Ok(value) => value,
        Err(err) => {
            debug!("create Build.{field} string failed: {err:?}");
            return;
        }
    };
    let object = JObject::from(value);

    let field_name = JNIString::new(field);
    let Ok(field_signature) = RuntimeFieldSignature::from_str("Ljava/lang/String;") else {
        debug!("parse Build.{field} signature failed");
        return;
    };
    if let Err(err) = env.set_static_field(
        class,
        &field_name,
        field_signature.field_signature(),
        JValue::Object(&object),
    ) {
        debug!("set Build.{field} failed: {err:?}");
    }
}

pub fn hook_system_properties(
    api: &mut ZygiskApi<'_, V4>,
    env: EnvUnowned<'_>,
    props: &'static [(&'static str, &'static str)],
) {
    debug!("hook android.os.SystemProperties native getters");

    let _ = SPOOFED_SYS_PROPS.set(props);

    let class_name: &JNIStr = unsafe { JNIStr::from_ptr(c"android/os/SystemProperties".as_ptr()) };
    let mut methods = [
        JNINativeMethod {
            name: c"native_get".as_ptr().cast_mut(),
            signature: c"(Ljava/lang/String;)Ljava/lang/String;"
                .as_ptr()
                .cast_mut(),
            fnPtr: my_native_get_one as *mut _,
        },
        JNINativeMethod {
            name: c"native_find".as_ptr().cast_mut(),
            signature: c"(Ljava/lang/String;)J".as_ptr().cast_mut(),
            fnPtr: my_native_find as *mut _,
        },
        JNINativeMethod {
            name: c"native_get".as_ptr().cast_mut(),
            signature: c"(J)Ljava/lang/String;".as_ptr().cast_mut(),
            fnPtr: my_native_get_handle as *mut _,
        },
        JNINativeMethod {
            name: c"native_get".as_ptr().cast_mut(),
            signature: c"(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"
                .as_ptr()
                .cast_mut(),
            fnPtr: my_native_get as *mut _,
        },
        JNINativeMethod {
            name: c"native_get_int".as_ptr().cast_mut(),
            signature: c"(Ljava/lang/String;I)I".as_ptr().cast_mut(),
            fnPtr: my_native_get_int as *mut _,
        },
        JNINativeMethod {
            name: c"native_get_long".as_ptr().cast_mut(),
            signature: c"(Ljava/lang/String;J)J".as_ptr().cast_mut(),
            fnPtr: my_native_get_long as *mut _,
        },
        JNINativeMethod {
            name: c"native_get_boolean".as_ptr().cast_mut(),
            signature: c"(Ljava/lang/String;Z)Z".as_ptr().cast_mut(),
            fnPtr: my_native_get_boolean as *mut _,
        },
    ];

    unsafe {
        api.hook_jni_native_methods(env, class_name, methods.as_mut_slice());
    }

    if !methods[0].fnPtr.is_null() {
        let orig_fn: NativeGetOneFn = unsafe { std::mem::transmute(methods[0].fnPtr) };
        let _ = ORIG_NATIVE_GET_ONE.set(orig_fn);
        debug!("hooked native_get(String): {:?}", methods[0].fnPtr);
    }
    if !methods[1].fnPtr.is_null() {
        let orig_fn: NativeFindFn = unsafe { std::mem::transmute(methods[1].fnPtr) };
        let _ = ORIG_NATIVE_FIND.set(orig_fn);
        debug!("hooked native_find: {:?}", methods[1].fnPtr);
    }
    if !methods[2].fnPtr.is_null() {
        let orig_fn: NativeHandleGetFn = unsafe { std::mem::transmute(methods[2].fnPtr) };
        let _ = ORIG_NATIVE_HANDLE_GET.set(orig_fn);
        debug!("hooked native_get(handle): {:?}", methods[2].fnPtr);
    }
    if !methods[3].fnPtr.is_null() {
        let orig_fn: NativeGetFn = unsafe { std::mem::transmute(methods[3].fnPtr) };
        let _ = ORIG_NATIVE_GET.set(orig_fn);
        debug!("hooked native_get(String,String): {:?}", methods[3].fnPtr);
    }
    if !methods[4].fnPtr.is_null() {
        let orig_fn: NativeGetIntFn = unsafe { std::mem::transmute(methods[4].fnPtr) };
        let _ = ORIG_NATIVE_GET_INT.set(orig_fn);
        debug!("hooked native_get_int: {:?}", methods[4].fnPtr);
    }
    if !methods[5].fnPtr.is_null() {
        let orig_fn: NativeGetLongFn = unsafe { std::mem::transmute(methods[5].fnPtr) };
        let _ = ORIG_NATIVE_GET_LONG.set(orig_fn);
        debug!("hooked native_get_long: {:?}", methods[5].fnPtr);
    }
    if !methods[6].fnPtr.is_null() {
        let orig_fn: NativeGetBooleanFn = unsafe { std::mem::transmute(methods[6].fnPtr) };
        let _ = ORIG_NATIVE_GET_BOOLEAN.set(orig_fn);
        debug!("hooked native_get_boolean: {:?}", methods[6].fnPtr);
    }
}

unsafe extern "C" fn my_native_find(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    key_j: jni::sys::jstring,
) -> jni::sys::jlong {
    let mut jni_env = unsafe { EnvUnowned::from_raw(env) };
    if key_j.is_null() {
        return 0;
    }
    let key = jstring_to_string(&mut jni_env, key_j);
    let Some(value) = spoofed_value(&key) else {
        return ORIG_NATIVE_FIND
            .get()
            .map(|orig| orig(env, clazz, key_j))
            .unwrap_or(0);
    };
    let handles = HANDLES.get_or_init(|| Mutex::new(Vec::new()));
    let Ok(mut handles) = handles.lock() else {
        return 0;
    };
    if let Some(index) = handles.iter().position(|item| *item == value) {
        return (index + 1) as jni::sys::jlong;
    }
    if handles.len() >= 256 {
        return 0;
    }
    handles.push(value);
    handles.len() as jni::sys::jlong
}

unsafe extern "C" fn my_native_get_handle(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    handle: jni::sys::jlong,
) -> jni::sys::jstring {
    if handle > 0 {
        if let Some(handles) = HANDLES.get() {
            if let Ok(handles) = handles.lock() {
                if let Some(value) = handles.get((handle - 1) as usize) {
                    let mut jni_env = unsafe { EnvUnowned::from_raw(env) };
                    if let Some(result) = new_string(&mut jni_env, value) {
                        return result;
                    }
                }
            }
        }
    }
    ORIG_NATIVE_HANDLE_GET
        .get()
        .map(|orig| orig(env, clazz, handle))
        .unwrap_or(std::ptr::null_mut())
}

unsafe extern "C" fn my_native_get_one(
    env: *mut jni::sys::JNIEnv,
    clazz: jni::sys::jclass,
    key_j: jni::sys::jstring,
) -> jni::sys::jstring {
    let mut jni_env = unsafe { EnvUnowned::from_raw(env) };
    let key = jstring_to_string(&mut jni_env, key_j);
    if let Some(value) = spoofed_value(&key) {
        return new_string(&mut jni_env, value).unwrap_or(std::ptr::null_mut());
    }
    match ORIG_NATIVE_GET_ONE.get() {
        Some(orig) => orig(env, clazz, key_j),
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::CString;

    use super::{
        copy_property_value, parse_bool, parse_int, parse_long, parse_mapping_device,
        should_hook_mapping,
    };

    #[test]
    fn parses_typed_property_values() {
        assert_eq!(parse_int("13"), Some(13));
        assert_eq!(parse_long("1625587200"), Some(1_625_587_200));
        assert_eq!(parse_bool("true"), Some(true));
        assert_eq!(parse_bool("0"), Some(false));
    }

    #[test]
    fn rejects_invalid_typed_property_values() {
        assert_eq!(parse_int("V130"), None);
        assert_eq!(parse_long("picasso"), None);
        assert_eq!(parse_bool("maybe"), None);
    }

    #[test]
    fn parses_proc_maps_device_and_filters_non_elf_entries() {
        assert_eq!(
            parse_mapping_device("fe:00"),
            Some(libc::makedev(0xfe, 0x00)),
        );
        assert!(should_hook_mapping("r-xp", "/system/lib64/libc.so"));
        assert!(should_hook_mapping("r-xp", "/data/app/base.apk"));
        assert!(!should_hook_mapping("rw-p", "/system/lib64/libc.so"));
        assert!(!should_hook_mapping("r-xp", "[vdso]"));
    }

    #[test]
    fn bounds_native_property_values_and_terminates_them() {
        let mut output = vec![0_i8; 128];
        let copied = copy_property_value(&"x".repeat(200), output.as_mut_ptr());
        assert_eq!(copied, 91);
        assert_eq!(output[91], 0);

        let key = CString::new("ro.product.brand").unwrap();
        assert_eq!(key.to_str().unwrap(), "ro.product.brand");
    }
}
