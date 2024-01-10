// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use std::time::Duration;

use anyhow::Result;
use argh::FromArgs;
use camino::Utf8PathBuf;
use serial_bridge::serial_bridge_protocol::{
    receive_message, send_message, GuestToHostMsg, HostToGuestMsg, TestOutput, TestStart,
};

use tokio::time::timeout;
use tokio_serial::SerialStream;
use uuid::Uuid;

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "send-start")]
/// inform host we are starting a test
struct SerBridgeSendTestStartCmd {
    #[argh(option, default = "Uuid::new_v4()")]
    /// unique execution ID to identify this test execution. Random ID will be
    /// generated if not provided
    test_execution_id: Uuid,

    #[argh(option)]
    /// name of the test that was executed
    test_name: String,
}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "send-results")]
/// inform host we finished a test
struct SerBridgeSendTestResultsCmd {
    #[argh(option, default = "Uuid::new_v4()")]
    /// unique execution ID to identify this test execution. Random ID will be
    /// generated if not provided
    test_execution_id: Uuid,

    #[argh(option)]
    /// name of the test that was executed
    test_name: String,

    #[argh(option)]
    /// file containing actual output from the test, whatever it may be
    test_output: Utf8PathBuf,

    #[argh(option)]
    /// what exit code did the test leave with?
    test_exit_code: u64,

    #[argh(option)]
    /// how long did the test take to run?
    test_runtime_millis: u64,

    #[argh(option)]
    /// any dmesg output generated during the test
    dmesg_output: String,
}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "send-done")]
/// tell the host that we are done running tests
struct SerBridgeSendDoneCmd {}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "request-test-list")]
/// request the list of tests to run from the host. if they reply with no tests,
/// or they never reply, we assume we should run everything.
struct SerBridgeRequestTestListCmd {}

#[derive(FromArgs, PartialEq, Debug)]
/// fio rig. see help for individual subcommands.
struct SerBridgeGuestCmd {
    #[argh(subcommand)]
    subcmd: SerBridgeGuestSubCmd,
}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand)]
enum SerBridgeGuestSubCmd {
    SendStart(SerBridgeSendTestStartCmd),
    SendTestResults(SerBridgeSendTestResultsCmd),
    RequestTestList(SerBridgeRequestTestListCmd),
    SendDone(SerBridgeSendDoneCmd),
}

#[tokio::main]
async fn main() -> Result<()> {
    let args: SerBridgeGuestCmd = argh::from_env();

    let mut ser = SerialStream::open(&tokio_serial::new("/dev/ttyS0", 115200))
        .expect("Failed to open serial port");

    let _: anyhow::Result<()> = match args.subcmd {
        SerBridgeGuestSubCmd::SendStart(cmd_data) => {
            let test_start = TestStart {
                execution_id: cmd_data.test_execution_id,
                name: cmd_data.test_name,
            };

            let msg = GuestToHostMsg::TestStart(test_start);
            send_message(&mut ser, &msg).await?;
            Ok(())
        }
        SerBridgeGuestSubCmd::SendTestResults(cmd_data) => {
            let output = tokio::fs::read(cmd_data.test_output).await?;
            let output = String::from_utf8_lossy(&output).to_string();

            let test_output = TestOutput {
                execution_id: cmd_data.test_execution_id,
                name: cmd_data.test_name,
                output,
                dmesg: cmd_data.dmesg_output,
                exitcode: cmd_data.test_exit_code,
                runtime_millis: cmd_data.test_runtime_millis,
            };
            let msg = GuestToHostMsg::TestOutput(test_output);
            send_message(&mut ser, &msg).await?;
            Ok(())
        }
        SerBridgeGuestSubCmd::RequestTestList(_) => {
            send_message(&mut ser, &GuestToHostMsg::WhatTestsShouldIRun()).await?;

            let response = receive_message(&mut ser);

            // if the other end
            // doesnt reply to our request for a list of tests to run, then we
            // will just run everything. and we dont need to worry about like,
            // discarding bytes or whatever, because if the other side doesnt
            // reply then there will never be any bytes anyway.
            let response = timeout(Duration::from_millis(5000), response).await;

            let jobs_to_run = match response {
                Ok(result) => match result? {
                    HostToGuestMsg::PleaseRunTheseTests(jobs) => jobs,
                },
                Err(_) => {
                    vec![]
                }
            };

            for job in jobs_to_run {
                println!("{}", job);
            }

            Ok(())
        }
        SerBridgeGuestSubCmd::SendDone(_) => {
            send_message(&mut ser, &GuestToHostMsg::Done()).await?;
            Ok(())
        }
    };

    Ok(())
}
