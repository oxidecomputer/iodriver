// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use argh::FromArgs;
use camino::Utf8PathBuf;
use serial_bridge::serial_bridge_protocol::{
    receive_message, send_message, GuestToHostMsg, HostToGuestMsg,
};

use tokio::{
    io::{self, AsyncWriteExt, BufReader},
    net::UnixStream,
};

#[derive(FromArgs, PartialEq, Debug)]
/// serial bridge host side. runs until guest says all tests are done.
struct SerBridgeHostCmd {
    #[argh(option)]
    /// path to vm's serial console
    vm_serial: Utf8PathBuf,

    #[argh(option)]
    /// list of specific jobs to run. you can specify multiple! If you dont pass
    /// in this variable, all available jobs will run. You can find the
    /// list of available jobs by looking at the jobs directory on the iodriver
    /// github repo. Each `.sh` file has a job, where the name is the same as
    /// the file name just without the `.sh`. So cool_job.sh would translate to
    /// --job cool_job
    job: Vec<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: SerBridgeHostCmd = argh::from_env();

    let job = args.job.clone();

    let stream = UnixStream::connect(&args.vm_serial).await?;

    let (read, mut write) = stream.into_split();

    // BufferedReader bufferedRead = new BufferedReader(UnixStream)
    let mut buf_stream = BufReader::new(read);
    let mut stdout = io::stdout();

    loop {
        let msg = receive_message(&mut buf_stream).await?;
        match msg {
            GuestToHostMsg::TestStart(start) => {
                eprintln!("Test starting: {} - {}", start.name, start.execution_id);
            }
            GuestToHostMsg::TestOutput(output) => {
                let out_json = serde_json::to_string_pretty(&output)?;
                stdout.write_all(out_json.as_bytes()).await?;
                stdout.write_u8(b'\n').await?;
                stdout.flush().await?;
            }
            GuestToHostMsg::WhatTestsShouldIRun() => {
                send_message(
                    &mut write,
                    &HostToGuestMsg::PleaseRunTheseTests(job.clone()),
                )
                .await?
            }
            GuestToHostMsg::Done() => break,
        }
    }

    Ok(())
}
