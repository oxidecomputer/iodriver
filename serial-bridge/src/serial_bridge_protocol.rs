// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use anyhow::{bail, Result};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::{collections::VecDeque, io::ErrorKind};
use tokio::io::{self, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufWriter};
use uuid::Uuid;

pub const ALIGNMENT_SEQUENCE: &[u8] = "==\"'= ALIGNMENT SEQUENCE - SOLSTICE =\"'==".as_bytes();

#[derive(PartialEq, Eq, Debug, Serialize, Deserialize)]
pub struct TestStart {
    pub execution_id: Uuid,
    pub name: String,
}

#[derive(PartialEq, Eq, Debug, Serialize, Deserialize)]
pub struct TestOutput {
    pub execution_id: Uuid,
    pub name: String,
    pub output: String,
    pub dmesg: String,
    pub exitcode: u64,
    pub runtime_millis: u64,
}

#[derive(PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum GuestToHostMsg {
    TestStart(TestStart),
    TestOutput(TestOutput),
    WhatTestsShouldIRun(),
    Done(),
}

#[derive(PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum HostToGuestMsg {
    PleaseRunTheseTests(Vec<String>),
}

pub async fn send_message<T: AsyncWrite + Unpin, J: Serialize>(
    stream: &mut T,
    msg: &J,
) -> Result<()> {
    let msg_json = serde_json::to_string(&msg)?.into_bytes();

    // I don't really want binary on the serial just so that we don't clog up
    // peoples' terminals if they want to view the output raw. So I'll use a
    // 0-padded fixed length number instead.
    let msg_json_len = format!("{:024}", msg_json.len()).into_bytes();

    stream.write_all(ALIGNMENT_SEQUENCE).await?;
    stream.write_all(&msg_json_len).await?;
    stream.write_all(&msg_json).await?;
    stream.flush().await?;
    Ok(())
}

pub async fn receive_message<T: AsyncRead + Unpin, J: DeserializeOwned>(
    stream: &mut T,
) -> Result<J> {
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
