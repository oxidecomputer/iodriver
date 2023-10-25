// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use anyhow::{bail, Result};
use argh::FromArgs;
use camino::Utf8PathBuf;
use serial_bridge::serial_bridge_protocol::{GuestToHostMsg, ALIGNMENT_SEQUENCE};
use std::{collections::VecDeque, io::ErrorKind};
use tokio::{
    io::{self, AsyncRead, AsyncReadExt, AsyncWriteExt, BufReader, BufWriter},
    net::UnixStream,
};

#[derive(FromArgs, PartialEq, Debug)]
/// serial bridge host side. runs until guest says all tests are done.
struct SerBridgeHostCmd {
    #[argh(option)]
    /// path to vm's serial console
    vm_serial: Utf8PathBuf,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args: SerBridgeHostCmd = argh::from_env();

    let stream = UnixStream::connect(&args.vm_serial).await?;

    // BufferedReader bufferedRead = new BufferedReader(UnixStream)
    let mut buf_stream = BufReader::new(stream);
    let mut stdout = io::stdout();

    loop {
        let msg = receive_message(&mut buf_stream).await?;
        match msg {
            GuestToHostMsg::TestOutput(output) => {
                let out_json = serde_json::to_string_pretty(&output)?;
                stdout.write_all(out_json.as_bytes()).await?;
                stdout.write_u8(b'\n').await?;
                stdout.flush().await?;
            }
            GuestToHostMsg::Done() => break,
        }
    }

    Ok(())
}

async fn receive_message<T: AsyncRead + Unpin>(stream: &mut T) -> Result<GuestToHostMsg> {
    let stderr = io::stderr();
    let mut stderr = BufWriter::new(stderr);
    // Wait for complete alignment sequence. We need this to skip over any
    // bootloader crud before the other end starts running.
    {
        // Scan through so we look at a [ segment ] the length of the alignment buffer.
        // One character goes in, one comes back out
        // 0   1   2   <-[ 3 4 5 6 7 ]<-   8   9   A
        let mut scanning_buffer = VecDeque::new();

        // Initiallize with zeroes matching the expected message length
        for _ in ALIGNMENT_SEQUENCE.iter() {
            scanning_buffer.push_back(0u8);
        }

        // Until we've read the alignment sequence, read one byte at a time.
        while !scanning_buffer.iter().eq(ALIGNMENT_SEQUENCE.iter()) {
            let mut byte = [0u8; 1];
            match stream.read(&mut byte).await {
                Ok(0) => bail!("Serial stream ended before alignment sequence was found."),
                Ok(1) => {
                    scanning_buffer.push_back(byte[0]);
                    let _ = scanning_buffer.pop_front();

                    // Forward the byte to stderr. This does mean that the
                    // alignment sequence will end up in stderr, but the json
                    // won't
                    stderr.write(&byte).await?;

                    // Flush stderr on \r or \n
                    if byte[0] == b'\r' || byte[0] == b'\n' {
                        stderr.flush().await?;
                    }
                }
                Ok(_) => unreachable!(),
                Err(e) if e.kind() == ErrorKind::WouldBlock => (), // read timeout, which is fine
                Err(e) if e.kind() == ErrorKind::Interrupted => (), // interrupted, which is fine
                Err(e) => bail!(e),                                // some unexpected error
            }
        }
    }

    // Flush the last of any stderr we need to write and then drop the writer
    stderr.write_u8(b'\n').await?;
    stderr.flush().await?;
    drop(stderr);

    // Read length of message
    let mut len_buf = [0u8; 24];
    stream.read_exact(&mut len_buf).await?;
    let len = usize::from_str_radix(&String::from_utf8(len_buf.to_vec())?, 10)?;

    // Read message
    let mut msg_buf = Vec::new();
    msg_buf.resize(len, 0);
    stream.read_exact(&mut msg_buf).await?;

    let msg = serde_json::from_slice(&msg_buf)?;

    Ok(msg)
}
