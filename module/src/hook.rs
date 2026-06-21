use std::sync::OnceLock;

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
static ORIG_NATIVE_GET_INT: OnceLock<NativeGetIntFn> = OnceLock::new();
static ORIG_NATIVE_GET_LONG: OnceLock<NativeGetLongFn> = OnceLock::new();
static ORIG_NATIVE_GET_BOOLEAN: OnceLock<NativeGetBooleanFn> = OnceLock::new();
static SPOOFED_SYS_PROPS: OnceLock<&'static [(&'static str, &'static str)]> = OnceLock::new();

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
        let orig_fn: NativeGetFn = unsafe { std::mem::transmute(methods[0].fnPtr) };
        let _ = ORIG_NATIVE_GET.set(orig_fn);
        debug!("hooked native_get: {:?}", methods[0].fnPtr);
    }
    if !methods[1].fnPtr.is_null() {
        let orig_fn: NativeGetIntFn = unsafe { std::mem::transmute(methods[1].fnPtr) };
        let _ = ORIG_NATIVE_GET_INT.set(orig_fn);
        debug!("hooked native_get_int: {:?}", methods[1].fnPtr);
    }
    if !methods[2].fnPtr.is_null() {
        let orig_fn: NativeGetLongFn = unsafe { std::mem::transmute(methods[2].fnPtr) };
        let _ = ORIG_NATIVE_GET_LONG.set(orig_fn);
        debug!("hooked native_get_long: {:?}", methods[2].fnPtr);
    }
    if !methods[3].fnPtr.is_null() {
        let orig_fn: NativeGetBooleanFn = unsafe { std::mem::transmute(methods[3].fnPtr) };
        let _ = ORIG_NATIVE_GET_BOOLEAN.set(orig_fn);
        debug!("hooked native_get_boolean: {:?}", methods[3].fnPtr);
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
