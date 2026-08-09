mod app;
mod config;
mod event;
mod globals;
mod kiss;
mod log;
mod logging;
mod message;
mod single_instance;
mod slash;
mod ui;

use app::App;
use color_eyre::Result;

fn main() -> Result<()> {
    color_eyre::install()?;

    // exit the process, even in the case of thread panics
    let default_panic_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        default_panic_hook(info);
        std::process::exit(1);
    }));

    // ensure only one instance runs on the machine
    let _instance = match single_instance::acquire()? {
        Some(guard) => guard,
        None => {
            eprintln!("kisstty is already running, exiting");
            std::process::exit(1);
        }
    };

    let _log_path = logging::init()?;
    tracing::info!("starting up kisstty");

    App::new().run()?;

    tracing::info!("shut down kisstty");
    Ok(())
}
