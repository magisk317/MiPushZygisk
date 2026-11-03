use android_logger::Config;
use jni::{Env, EnvUnowned};
use log::{debug, error, info, LevelFilter};
use std::os::unix::net::UnixStream;
use zygisk_api::{
    api::{v4::ZygiskOption, ZygiskApi, V4},
    raw::ZygiskRaw,
    register_companion, register_module, ZygiskModule,
};

mod config;
use config::XMSF_PACKAGE_NAME;
mod hook;
mod protocol;
mod server;

#[derive(Default)]
struct MiPushZygiskModule;

impl ZygiskModule for MiPushZygiskModule {
    type Api = V4;

    fn pre_app_specialize<'a>(
        &self,
        mut api: ZygiskApi<'a, V4>,
        mut env: EnvUnowned<'a>,
        args: &'a mut <V4 as ZygiskRaw<'_>>::AppSpecializeArgs,
    ) {
        android_logger::init_once(
            Config::default()
                .with_max_level(LevelFilter::Debug)
                .with_tag("MiPushZygisk"),
        );

        let raw_env = env.as_raw();
        let process_name = jstring_to_string(&mut env, args.nice_name);
        let app_data_dir = jstring_to_string(&mut env, args.app_data_dir);
        if process_name.is_empty() || app_data_dir.is_empty() {
            api.set_option(ZygiskOption::DlCloseModuleLibrary);
            return;
        }

        let package_name = parse_package_name(&app_data_dir);
        debug!("pre_app_specialize pkg={package_name} process={process_name}");

        unsafe { EnvUnowned::from_raw(raw_env) }
            .with_env_no_catch(|env| {
                pre_specialize(api, env, package_name, &process_name);
                Ok::<_, jni::errors::Error>(())
            })
            .into_outcome();
    }

    fn pre_server_specialize<'a>(
        &self,
        mut api: ZygiskApi<'a, V4>,
        _env: EnvUnowned<'a>,
        _args: &'a mut <V4 as ZygiskRaw<'_>>::ServerSpecializeArgs,
    ) {
        api.set_option(ZygiskOption::DlCloseModuleLibrary);
    }
}

fn jstring_to_string(env: &mut EnvUnowned<'_>, jstr: &jni::objects::JString<'_>) -> String {
    env.with_env_no_catch(|env| Ok::<_, jni::errors::Error>(jstr.mutf8_chars(env)?.to_string()))
        .resolve::<jni::errors::LogErrorAndDefault>()
}

fn parse_package_name(app_data_dir: &str) -> &str {
    app_data_dir
        .rsplit('/')
        .find(|part| !part.is_empty())
        .unwrap_or("")
}

fn pre_specialize(
    mut api: ZygiskApi<'_, V4>,
    env: &mut Env<'_>,
    package_name: &str,
    process_name: &str,
) {
    let runtime_config = if package_name == XMSF_PACKAGE_NAME {
        None
    } else {
        query_runtime_config(&mut api, package_name, process_name)
    };
    let should_hook = package_name == XMSF_PACKAGE_NAME
        || runtime_config
            .as_ref()
            .is_some_and(|config| config.should_hook);

    if should_hook {
        info!("spoof Xiaomi props for pkg={package_name} process={process_name}");

        let profile = runtime_config
            .as_ref()
            .map_or(config::Profile::Miui14, |config| {
                config::Profile::from_wire(config.profile)
            });
        let device_config = runtime_config
            .as_ref()
            .and_then(|config| std::str::from_utf8(&config.device_config).ok());
        let props = config::get_properties_for_package(package_name, profile, device_config);

        if !props.build_properties.is_empty() || !props.build_version_properties.is_empty() {
            hook::hook_build(env, props.build_properties, props.build_version_properties);
        }

        if !props.system_properties.is_empty() {
            let unowned = unsafe { EnvUnowned::from_raw(env.get_raw()) };
            hook::hook_system_properties(
                &mut api,
                unowned,
                props.system_properties,
                runtime_config.as_ref().is_some_and(|config| config.observe),
            );
        }
    } else {
        api.set_option(ZygiskOption::DlCloseModuleLibrary);
    }
}

fn query_runtime_config(
    api: &mut ZygiskApi<'_, V4>,
    package_name: &str,
    process_name: &str,
) -> Option<protocol::RuntimeConfig> {
    let result = api.with_companion(|stream| send_query(stream, package_name, process_name));
    match result {
        Ok(Ok(config)) => Some(config),
        Ok(Err(err)) => {
            error!("companion query failed: {err:?}");
            None
        }
        Err(err) => {
            error!("companion unavailable: {err:?}");
            None
        }
    }
}

fn send_query(
    stream: &mut UnixStream,
    package_name: &str,
    process_name: &str,
) -> std::io::Result<protocol::RuntimeConfig> {
    if let Err(err) = protocol::configure(stream).and_then(|_| {
        protocol::write_frame(
            stream,
            protocol::QUERY,
            &protocol::encode_query(package_name, process_name),
        )
    }) {
        error!("send companion query failed: {err}");
        return Err(err);
    }
    protocol::read_frame(stream).and_then(|(kind, payload)| {
        if kind != protocol::RESPONSE {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "unexpected response",
            ));
        }
        protocol::decode_response(&payload)
    })
}

register_module!(MiPushZygiskModule);
register_companion!(server::companion_handler);
