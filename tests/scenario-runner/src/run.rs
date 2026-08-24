//! Driving one scenario: preflight, the step loop, and the summary.

use crate::scenario::{Scenario, Step};
use crate::ui::{Answer, Ui};
use kisstty_harness::{Direwolf, HarnessError, LoremSource, RawSession, Serial, escape, unescape};
use std::path::PathBuf;
use std::time::{Duration, Instant};

pub struct Run<'a> {
    s: &'a Scenario,
    ui: Ui,
    serial: String,
    port: u16,
    template: PathBuf,
    failures: Vec<String>,
    pub stopped_at: Option<usize>,
    dw: Option<Direwolf>,
    ser: Option<Serial>,
    rng: LoremSource,
}

impl<'a> Run<'a> {
    pub fn new(s: &'a Scenario, ui: Ui, serial: String, port: u16, template: PathBuf) -> Self {
        Self {
            s,
            ui,
            serial,
            port,
            template,
            failures: Vec::new(),
            stopped_at: None,
            dw: None,
            ser: None,
            rng: LoremSource::new(None),
        }
    }

    pub fn preview(&self) {
        let ui = &self.ui;
        let s = self.s;
        ui.title(&s.name, &s.platform);
        let act = s.steps.iter().filter(|x| x.needs_you_to_act()).count();
        let look = s.steps.iter().filter(|x| x.needs_you_to_look()).count();
        let auto = s
            .steps
            .iter()
            .filter(|x| !x.needs_you_to_act() && !x.needs_you_to_look())
            .count();
        println!();
        println!(
            "   {} steps in this scenario:",
            ui.bold(&s.steps.len().to_string())
        );
        if act > 0 {
            println!(
                "     {}  {act} need you to act",
                ui.tag("ACTION NEEDED", "30;43;1")
            );
        }
        if look > 0 {
            println!(
                "     {} {look} need you to check the screen and answer",
                ui.tag("LOOK AT SCREEN", "30;46;1")
            );
        }
        if auto > 0 {
            println!(
                "     {}  {auto} run on their own",
                ui.dim(".. WORKING      ")
            );
        }
        if s.steps.iter().any(|x| x.repeat == 0) {
            println!(
                "   {}",
                ui.yellow("one step repeats until you press q or ctrl-c")
            );
        }
        println!();
        if s.uses_air() {
            let where_ = if self.serial.is_empty() {
                format!("KISS over TCP on port {}", self.port)
            } else {
                format!("KISS over serial on {}", self.serial)
            };
            println!("{}", ui.dim(&format!("   {where_}")));
        } else if s.uses_wire() {
            println!(
                "{}",
                ui.dim(&format!(
                    "   driving the serial device on {} directly",
                    self.serial
                ))
            );
        } else {
            println!(
                "{}",
                ui.dim("   no step sends or checks a packet, so direwolf is not started")
            );
        }
    }

    /// Returns `Ok(false)` if the user quit at the setup prompt.
    pub fn start_hardware(&mut self) -> Result<bool, HarnessError> {
        let s = self.s;
        if s.uses_air() {
            self.ui.setup(
                &[
                    format!("Set your kisstty callsign to {}", self.ui.bold(&s.mycall)),
                    "(no SSID unless a step shows one)".to_string(),
                ],
                "press Enter when it is set, q to quit",
            );
            if matches!(self.ui.finish_setup_prompt(), Answer::Quit) {
                return Ok(false);
            }
            let dw = Direwolf::start(
                &self.template,
                &self.serial,
                &s.mycall,
                "kisstty-scenario",
                self.port,
            )?;
            println!(
                "{}",
                self.ui.dim(&format!(
                    "   direwolf up, log at {}",
                    dw.log_path().display()
                ))
            );
            self.dw = Some(dw);
        } else if s.uses_wire() {
            self.ser = Some(Serial::open(&self.serial)?);
        }
        Ok(true)
    }

    pub fn stop_hardware(&mut self) {
        if let Some(mut dw) = self.dw.take() {
            let log = dw.log_path().to_path_buf();
            dw.stop();
            println!(
                "{}",
                self.ui.dim(&format!(
                    "   direwolf stopped, log kept at {}",
                    log.display()
                ))
            );
        }
        // Serial has no explicit close; dropping it is enough (see harness).
        self.ser = None;
    }

    pub fn run(&mut self) {
        let total = self.s.steps.len();
        let s = self.s;
        for step in &s.steps {
            self.ui.step_header(step.index, total, &step.description);
            // Each step reads only what happened during it, so an earlier
            // step's frame can neither satisfy nor trip a check.
            if let Some(dw) = self.dw.as_mut() {
                dw.new_log();
            }
            if let Some(ser) = self.ser.as_ref() {
                ser.new_window();
            }
            if !self.step(step) {
                self.stopped_at = Some(step.index);
                return;
            }
        }
    }

    /// Runs one step's verbs in order. `false` means the user quit.
    fn step(&mut self, step: &Step) -> bool {
        if !step.do_.is_empty() && !self.do_step(step) {
            return false;
        }
        if !step.to_kisstty.is_empty() || step.random {
            self.inject_step(step);
        }
        if !step.to_serial.is_empty() {
            self.to_serial_step(step);
        }
        if let Some(wait) = step.wait {
            self.ui.working_banner();
            self.sleep_with_progress(wait, "waiting", None);
        }
        if !step.from_kisstty.is_empty() {
            self.from_kisstty_step(step);
        }
        if !step.not_from_kisstty.is_empty() {
            self.not_from_kisstty_step(step);
        }
        if !step.from_serial.is_empty() {
            self.from_serial_step(step);
        }
        if !step.look_for.is_empty() && !self.look_for_step(step) {
            return false;
        }
        true
    }

    fn fail(&mut self, step: &Step, message: String) {
        self.failures
            .push(format!("step {}: {message}", step.index));
    }

    fn do_step(&mut self, step: &Step) -> bool {
        self.ui.action_banner();
        if step.do_.len() == 1 {
            self.ui.bullet(&self.ui.bold(&step.do_[0]));
        } else {
            for (i, line) in step.do_.iter().enumerate() {
                self.ui.bullet(&self.ui.bold(&format!("{}. {line}", i + 1)));
            }
        }
        !matches!(self.ui.ask("Enter when done, q to quit"), Answer::Quit)
    }

    fn inject_step(&mut self, step: &Step) {
        self.ui.working_banner();
        // Only a repeat-forever step needs a stop key: a counted repeat
        // already ends on its own, and reading stdin here would fight
        // whatever the step does next.
        let raw = (step.repeat == 0).then(kisstty_harness::raw_session);
        if step.repeat == 0 {
            let dot = self.ui.dim(self.ui.dot());
            let msg = self
                .ui
                .dim("repeating -- press q to stop, or ctrl-c to quit");
            self.ui.detail(&dot, &msg);
        }

        let mut done = 0u64;
        let mut first = true;
        loop {
            let packets: Vec<String> = if step.to_kisstty.is_empty() {
                vec![self.rng.packet()]
            } else {
                step.to_kisstty.clone()
            };
            for packet in &packets {
                // `every` spaces every packet after the very first, inside
                // a list and across repeats alike.
                if !first && self.sleep_with_progress(step.every, "next packet in", raw.as_ref()) {
                    return;
                }
                first = false;
                let air = self.ui.dim("air ");
                self.ui.detail(self.ui.to_air(), &format!("{air} {packet}"));
                let dw = self
                    .dw
                    .as_mut()
                    .expect("direwolf runs whenever a step injects");
                if let Err(e) = dw.inject(packet) {
                    self.ui.failed("inject", &e.to_string());
                    self.fail(step, format!("inject failed: {e}"));
                    return;
                }
            }
            done += 1;
            if step.repeat != 0 && done >= step.repeat {
                return;
            }
            if let Some(r) = &raw
                && matches!(r.poll_key(), Some(b'q' | b'Q'))
            {
                return;
            }
        }
    }

    fn to_serial_step(&mut self, step: &Step) {
        self.ui.working_banner();
        for chunk in &step.to_serial {
            let data = unescape(chunk).expect("validated at load");
            let wire = self.ui.dim("wire");
            self.ui
                .detail(self.ui.to_wire(), &format!("{wire} {}", escape(&data)));
            let ser = self
                .ser
                .as_mut()
                .expect("serial is open whenever a step writes to it");
            if let Err(e) = ser.write(&data) {
                self.ui.failed("write", &e.to_string());
                self.fail(step, e.to_string());
            }
        }
    }

    /// Sleeps up to `seconds`, showing a countdown. Returns `true` if `raw`
    /// saw a 'q' partway through and the sleep was cut short.
    fn sleep_with_progress(&mut self, seconds: u64, label: &str, raw: Option<&RawSession>) -> bool {
        if seconds == 0 {
            return false;
        }
        let deadline = Instant::now() + Duration::from_secs(seconds);
        while Instant::now() < deadline {
            if let Some(r) = raw
                && matches!(r.poll_key(), Some(b'q' | b'Q'))
            {
                self.ui.progress_done();
                return true;
            }
            self.ui.progress(label, deadline);
            std::thread::sleep(Duration::from_millis(200));
        }
        self.ui.progress_done();
        false
    }

    fn from_kisstty_step(&mut self, step: &Step) {
        self.ui.working_banner();
        let timeout = Duration::from_secs(step.timeout);
        let (ok, seen, log_path) = {
            let ui = &mut self.ui;
            let dw = self
                .dw
                .as_mut()
                .expect("direwolf runs whenever a step checks a frame");
            let (ok, seen) = dw
                .wait_for_log(&step.from_kisstty, timeout, |deadline| {
                    ui.progress("listening for the frame", deadline)
                })
                .expect("direwolf runs whenever a step checks a frame");
            ui.progress_done();
            (ok, seen, dw.log_path().to_path_buf())
        };
        for want in &step.from_kisstty {
            if ok {
                self.ui.passed("heard", want);
            } else {
                self.ui.failed("heard", want);
            }
        }
        if !ok {
            for want in &step.from_kisstty {
                self.fail(step, format!("kisstty never sent: {want}"));
            }
            self.ui.note(&format!(
                "nothing matched in {}s. a late frame would still land in\n{}, worth \
                 checking before believing it was never sent.",
                step.timeout,
                log_path.display()
            ));
            self.ui.log_dump(&seen);
        }
    }

    fn not_from_kisstty_step(&mut self, step: &Step) {
        self.ui.working_banner();
        let timeout = Duration::from_secs(step.timeout);
        let (ok, seen) = {
            let ui = &mut self.ui;
            let dw = self
                .dw
                .as_mut()
                .expect("direwolf runs whenever a step checks a frame");
            let result = dw
                .wait_for_no_log(&step.not_from_kisstty, timeout, |deadline| {
                    ui.progress("listening, should stay quiet", deadline)
                })
                .expect("direwolf runs whenever a step checks a frame");
            ui.progress_done();
            result
        };
        for want in &step.not_from_kisstty {
            if ok {
                self.ui.passed("silent", want);
            } else {
                self.ui.failed("silent", want);
            }
        }
        if !ok {
            for want in &step.not_from_kisstty {
                self.fail(step, format!("kisstty sent: {want}"));
            }
            self.ui.log_dump(&seen);
        }
    }

    fn from_serial_step(&mut self, step: &Step) {
        self.ui.working_banner();
        let timeout = Duration::from_secs(step.timeout);
        let wants: Vec<Vec<u8>> = step
            .from_serial
            .iter()
            .map(|w| unescape(w).expect("validated at load"))
            .collect();
        let (ok, seen) = {
            let ui = &mut self.ui;
            let ser = self
                .ser
                .as_ref()
                .expect("serial is open whenever a step checks it");
            let result = ser.expect(&wants, timeout, |deadline| {
                ui.progress("listening on the wire", deadline)
            });
            ui.progress_done();
            result
        };
        for want in &step.from_serial {
            if ok {
                self.ui.passed("wire", want);
            } else {
                self.ui.failed("wire", want);
            }
        }
        if !ok {
            for want in &step.from_serial {
                self.fail(step, format!("never arrived on serial: {want}"));
            }
            self.ui.note(&format!(
                "serial carried during this step: {}",
                escape(&seen)
            ));
        }
    }

    fn look_for_step(&mut self, step: &Step) -> bool {
        self.ui.look_banner();
        for want in &step.look_for {
            self.ui.bullet(&format!("{} {want}", self.ui.box_marker()));
        }
        match self.ui.ask("is that what you see? [Y/n/q]") {
            Answer::No => {
                for want in &step.look_for {
                    self.fail(step, format!("did not see: {want}"));
                }
                true
            }
            Answer::Quit => false,
            Answer::Yes => true,
        }
    }

    pub fn summary(&mut self) -> i32 {
        let ui = &self.ui;
        let s = self.s;
        println!();
        ui.rule(
            &format!(
                "{}{}",
                ui.bold(&s.name),
                ui.dim(&format!(" . {}", s.platform))
            ),
            true,
        );
        let ran = self.stopped_at.map(|n| n - 1).unwrap_or(s.steps.len());
        if !self.failures.is_empty() {
            println!(
                "   {}   {}",
                ui.red(&format!("XX {} failed", self.failures.len())),
                ui.dim(&format!("{ran} of {} steps ran", s.steps.len()))
            );
        } else if self.stopped_at.is_some() {
            println!(
                "   {}   {}",
                ui.yellow("stopped early"),
                ui.dim(&format!(
                    "{ran} of {} steps ran, none failed",
                    s.steps.len()
                ))
            );
        } else {
            println!(
                "   {}   {}",
                ui.green("OK passed"),
                ui.dim(&format!("all {} steps", s.steps.len()))
            );
        }
        if let Some(n) = self.stopped_at {
            println!("{}", ui.dim(&format!("   you quit at step {n}")));
        }
        for f in &self.failures {
            let (step_no, rest) = f.split_once(": ").unwrap_or((f.as_str(), ""));
            println!("     {:<20} {rest}", ui.red(step_no));
        }
        println!();
        // Quitting counts as not passing, since the remaining steps never
        // ran.
        if self.failures.is_empty() && self.stopped_at.is_none() {
            0
        } else {
            1
        }
    }
}
