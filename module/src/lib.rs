use android_logger::Config;
use jni::JNIEnv;
use log::{debug, error, info, LevelFilter};
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use zygisk_api::{
    api::{v4::ZygiskOption, ZygiskApi, V4},
    raw::ZygiskRaw,
    register_companion, register_module, ZygiskModule,
};

mod config;
use config::XMSF_PACKAGE_NAME;
mod hook;
mod server;

#[derive(Default)]
struct MiPushZygiskModule;

impl ZygiskModule for MiPushZygiskModule {
    type Api = V4;

    fn pre_app_specialize<'a>(
        &self,
        mut api: ZygiskApi<'a, V4>,
        mut env: JNIEnv<'a>,
        args: &'a mut <V4 as ZygiskRaw<'_>>::AppSpecializeArgs,
    ) {
        android_logger::init_once(
            Config::default()
                .with_max_level(LevelFilter::Debug)
                .with_tag("MiPushZygisk"),
        );

        let process_name = jstring_to_string(&mut env, args.nice_name);
        let app_data_dir = jstring_to_string(&mut env, args.app_data_dir);
        if process_name.is_empty() || app_data_dir.is_empty() {
            api.set_option(ZygiskOption::DlCloseModuleLibrary);
            return;
        }

        let package_name = parse_package_name(&app_data_dir);
        debug!("pre_app_specialize pkg={package_name} process={process_name}");

        pre_specialize(api, env, package_name, &process_name);
    }

    fn pre_server_specialize<'a>(
        &self,
        mut api: ZygiskApi<'a, V4>,
        _env: JNIEnv<'a>,
        _args: &'a mut <V4 as ZygiskRaw<'_>>::ServerSpecializeArgs,
    ) {
        api.set_option(ZygiskOption::DlCloseModuleLibrary);
    }
}

fn jstring_to_string(env: &mut JNIEnv<'_>, jstr: &jni::objects::JString<'_>) -> String {
    env.get_string(jstr).map(Into::into).unwrap_or_default()
}

fn parse_package_name(app_data_dir: &str) -> &str {
    app_data_dir
        .rsplit('/')
        .find(|part| !part.is_empty())
        .unwrap_or("")
}

fn pre_specialize(
    mut api: ZygiskApi<'_, V4>,
    mut env: JNIEnv<'_>,
    package_name: &str,
    process_name: &str,
) {
    let should_hook = package_name == XMSF_PACKAGE_NAME
        || query_should_hook(&mut api, package_name, process_name);

    if should_hook {
        info!("spoof Xiaomi props for pkg={package_name} process={process_name}");

        let props = config::get_properties_for_package(package_name);

        if !props.build_properties.is_empty() || !props.build_version_properties.is_empty() {
            hook::hook_build(
                &mut env,
                props.build_properties,
                props.build_version_properties,
            );
        }

        if !props.system_properties.is_empty() {
            hook::hook_system_properties(&mut api, env, props.system_properties);
        }
    } else {
        api.set_option(ZygiskOption::DlCloseModuleLibrary);
    }
}

fn query_should_hook(api: &mut ZygiskApi<'_, V4>, package_name: &str, process_name: &str) -> bool {
    let result = api.with_companion(|stream| send_query(stream, package_name, process_name));
    match result {
        Ok(should_hook) => should_hook,
        Err(err) => {
            error!("companion unavailable: {err:?}");
            false
        }
    }
}

fn send_query(stream: &mut UnixStream, package_name: &str, process_name: &str) -> bool {
    let payload = format!("{package_name}\n{process_name}\n");
    if let Err(err) = stream.write_all(payload.as_bytes()) {
        error!("send companion query failed: {err}");
        return false;
    }

    let mut response = [0u8; 1];
    match stream.read_exact(&mut response) {
        Ok(_) => response[0] != 0,
        Err(err) => {
            error!("read companion response failed: {err}");
            false
        }
    }
}

register_module!(MiPushZygiskModule);
register_companion!(server::companion_handler);
