// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use anyhow::Result;
use argh::FromArgs;
use camino::Utf8PathBuf;
use serial_bridge::serial_bridge_protocol::{GuestToHostMsg, TestOutput, ALIGNMENT_SEQUENCE};
use tokio::io::AsyncWriteExt;
use tokio_serial::SerialStream;
use uuid::Uuid;

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "send-results")]
/// serial bridge guest side
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
/// fio rig. see help for individual subcommands.
struct SerBridgeGuestCmd {
    #[argh(subcommand)]
    subcmd: SerBridgeGuestSubCmd,
}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand)]
enum SerBridgeGuestSubCmd {
    SendTestResults(SerBridgeSendTestResultsCmd),
    SendDone(SerBridgeSendDoneCmd),
}

#[tokio::main]
async fn main() -> Result<()> {
    let args: SerBridgeGuestCmd = argh::from_env();

    let msg = match args.subcmd {
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
            GuestToHostMsg::TestOutput(test_output)
        }
        SerBridgeGuestSubCmd::SendDone(_) => GuestToHostMsg::Done(),
    };

    let msg_json = serde_json::to_string(&msg)?.into_bytes();

    // I don't really want binary on the serial just so that we don't clog up
    // peoples' terminals if they want to view the output raw. So I'll use a
    // 0-padded fixed length number instead.
    let msg_json_len = format!("{:024}", msg_json.len()).into_bytes();

    let mut ser = SerialStream::open(&tokio_serial::new("/dev/ttyS0", 115200))
        .expect("Failed to open serial port");

    eprintln!("Writing data.");
    ser.write_all(ALIGNMENT_SEQUENCE).await?;
    ser.write_all(&msg_json_len).await?;
    ser.write_all(&msg_json).await?;
    ser.flush().await?;

    Ok(())
}
