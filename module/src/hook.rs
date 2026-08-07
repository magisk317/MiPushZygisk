use std::sync::{Mutex, OnceLock};

use jni::{
    objects::{JClass, JObject, JString, JValue},
    strings::JNIStr,
    sys::JNINativeMethod,
    JNIEnv,
};
use log::debug;
use zygisk_api::api::{ZygiskApi, V4};

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
    let mut jni_env = match JNIEnv::from_raw(env) {
        Ok(env) => env,
        Err(_) => return def_j,
    };

    let key: String = if key_j.is_null() {
        String::new()
    } else {
        let raw = JString::from_raw(key_j);
        let key = jni_env.get_string(&raw).map(Into::into).unwrap_or_default();
        let _ = raw.into_raw();
        key
    };

    if let Some(value) = spoofed_value(&key) {
        return match jni_env.new_string(value) {
            Ok(result) => result.into_raw(),
            Err(_) => def_j,
        };
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
    let mut jni_env = JNIEnv::from_raw(env).ok()?;
    let raw = JString::from_raw(key_j);
    let key: String = jni_env.get_string(&raw).map(Into::into).unwrap_or_default();
    let _ = raw.into_raw();
    spoofed_value(&key)
}

fn spoofed_value(key: &str) -> Option<&'static str> {
    observe_key(key);
    SPOOFED_SYS_PROPS
        .get()
        .and_then(|props| props.iter().find(|(prop, _)| *prop == key))
        .map(|(_, value)| *value)
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

pub fn hook_build(env: &mut JNIEnv<'_>, props: &[(&str, &str)], version_props: &[(&str, &str)]) {
    debug!("hook android.os.Build");

    let build_class = match env.find_class("android/os/Build") {
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
    let version_class = match env.find_class("android/os/Build$VERSION") {
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

fn set_static_string_field(env: &mut JNIEnv<'_>, class: &JClass<'_>, field: &str, value: &str) {
    let field_id = match env.get_static_field_id(class, field, "Ljava/lang/String;") {
        Ok(id) => id,
        Err(err) => {
            debug!("get Build.{field} failed: {err:?}");
            return;
        }
    };

    let value = match env.new_string(value) {
        Ok(value) => value,
        Err(err) => {
            debug!("create Build.{field} string failed: {err:?}");
            return;
        }
    };
    let object = JObject::from(value);

    if let Err(err) = env.set_static_field(class, field_id, JValue::Object(&object)) {
        debug!("set Build.{field} failed: {err:?}");
    }
}

pub fn hook_system_properties(
    api: &mut ZygiskApi<'_, V4>,
    env: JNIEnv<'_>,
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
    let mut jni_env = match JNIEnv::from_raw(env) {
        Ok(env) => env,
        Err(_) => return 0,
    };
    if key_j.is_null() {
        return 0;
    }
    let raw = JString::from_raw(key_j);
    let key: String = jni_env.get_string(&raw).map(Into::into).unwrap_or_default();
    let _ = raw.into_raw();
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
                    if let Ok(jni_env) = JNIEnv::from_raw(env) {
                        if let Ok(result) = jni_env.new_string(value) {
                            return result.into_raw();
                        }
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
    let mut jni_env = match JNIEnv::from_raw(env) {
        Ok(env) => env,
        Err(_) => return std::ptr::null_mut(),
    };
    let key = if key_j.is_null() {
        String::new()
    } else {
        let raw = JString::from_raw(key_j);
        let value = jni_env.get_string(&raw).map(Into::into).unwrap_or_default();
        let _ = raw.into_raw();
        value
    };
    if let Some(value) = spoofed_value(&key) {
        return jni_env
            .new_string(value)
            .map(|value| value.into_raw())
            .unwrap_or(std::ptr::null_mut());
    }
    match ORIG_NATIVE_GET_ONE.get() {
        Some(orig) => orig(env, clazz, key_j),
        None => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_bool, parse_int, parse_long};

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
}
