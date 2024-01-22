// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use std::{
    io::ErrorKind,
    pin::Pin,
    task::{ready, Poll},
};

use anyhow::bail;
use argh::FromArgs;
use camino::Utf8PathBuf;
use reqwest::Upgraded;
use serial_bridge::serial_bridge_protocol::{
    receive_message, send_message, GuestToHostMsg, HostToGuestMsg,
};

use tokio::{
    io::{self, AsyncRead, AsyncWrite, AsyncWriteExt, BufStream},
    net::UnixStream,
};
use tokio_tungstenite::{tungstenite::protocol::frame::coding::CloseCode, WebSocketStream};
use url::Url;

use oxide::{types::InstanceState, ClientInstancesExt};

use futures_util::{Sink, Stream};

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "unix")]
/// Connect to a unix socket created by propolis as the host end of a VM's
/// serial console
struct SerBridgeHostUnixCmd {
    #[argh(option)]
    /// path to vm's serial console.
    vm_serial: Utf8PathBuf,
}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand, name = "rack")]
/// Connect to a unix socket created by propolis as the host end of a VM's
/// serial console
struct SerBridgeHostRackCmd {
    #[argh(option)]
    /// base URL of the rack's API endpoint. For example,
    /// http://some.rack.in.a.oxide.computer/
    rack_addr: Url,

    #[argh(option)]
    /// instance ID in the rack
    instance: String,
}

#[derive(FromArgs, PartialEq, Debug)]
#[argh(subcommand)]
enum SerBridgeHostSubCmd {
    Unix(SerBridgeHostUnixCmd),
    Rack(SerBridgeHostRackCmd),
}

#[derive(FromArgs, PartialEq, Debug)]
/// serial bridge host side. runs until guest says all tests are done.
struct SerBridgeHostCmd {
    #[argh(subcommand)]
    subcmd: SerBridgeHostSubCmd,

    #[argh(option)]
    /// list of specific jobs to run. you can specify multiple! If you dont pass
    /// in this variable, all available jobs will run. You can find the
    /// list of available jobs by looking at the jobs directory on the iodriver
    /// github repo. Each `.sh` file has a job, where the name is the same as
    /// the file name just without the `.sh`. So cool_job.sh would translate to
    /// --job cool_job
    job: Vec<String>,
}

trait ICanReadAndWriteWhichNobodyExpected: AsyncRead + AsyncWrite {}
impl ICanReadAndWriteWhichNobodyExpected for BufStream<UnixStream> {}
impl ICanReadAndWriteWhichNobodyExpected for TungsteniteSerialStream {}

struct TungsteniteSerialStream {
    wss: WebSocketStream<Upgraded>,
    msg_buf: Vec<u8>,
}

fn tf_tungstenite_err_into_stdio(e: tokio_tungstenite::tungstenite::Error) -> std::io::Error {
    match e {
        tokio_tungstenite::tungstenite::Error::Io(e) => e,
        otherwise => std::io::Error::new(
            ErrorKind::Other,
            format!("Tungstenite Error: {:?}", otherwise),
        ),
    }
}

/// Implement a streaming view over the Binary(Vec<u8>) messages from a websocket client.
/// - Text messages are ignored
/// - Websocket IO errors are bubbled up as-is to the read IO error
/// - Other websocket errors are converted to io::Error::ErrorKind::Other, with
///   the websocket error returned in the error context string
///   - This includes in-band errors sent by the server at websocket close.
impl AsyncRead for TungsteniteSerialStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        let self_ = self.get_mut();

        // We have some data in the buffer already. Return from that. Note that
        // currently if we have less data than requested, we return less data
        // than requested, as we are allowed to do.
        if !self_.msg_buf.is_empty() {
            let to_read = buf.remaining().min(self_.msg_buf.len());
            let things_im_reading = self_.msg_buf.drain(0..to_read).collect::<Vec<_>>();
            buf.put_slice(&things_im_reading);
            return Poll::Ready(Ok(()));
        }

        // We didn't have any data in the buffer, so read the next websocket
        // message
        let wss = Pin::new(&mut self_.wss);
        let msg = ready!(wss.poll_next(cx));
        match msg {
            // End of websocket stream
            None => Poll::Ready(Ok(())),

            // Stream-level error
            Some(Err(e)) => Poll::Ready(Err(tf_tungstenite_err_into_stdio(e))),

            // Websocket message
            Some(Ok(msg)) => match msg {
                // Binary message. This is the data we are actually reading
                tokio_tungstenite::tungstenite::Message::Binary(bytes) => {
                    // msg_buf is empty, so we can just drop it and replace it
                    // with the new message bytes
                    self_.msg_buf = bytes;
                    let to_read = buf.remaining().min(self_.msg_buf.len());
                    let things_im_reading = self_.msg_buf.drain(0..to_read).collect::<Vec<_>>();
                    buf.put_slice(&things_im_reading);
                    Poll::Ready(Ok(()))
                }

                // Close without message, EOF
                tokio_tungstenite::tungstenite::Message::Close(None) => Poll::Ready(Ok(())),

                // Close with message.
                tokio_tungstenite::tungstenite::Message::Close(Some(close_frame)) => {
                    match close_frame.code {
                        // Generic Error
                        CloseCode::Error
                        | CloseCode::Protocol
                        | CloseCode::Unsupported
                        | CloseCode::Abnormal
                        | CloseCode::Invalid
                        | CloseCode::Policy
                        | CloseCode::Size
                        | CloseCode::Extension
                        | CloseCode::Restart
                        | CloseCode::Again => Poll::Ready(Err(io::Error::new(
                            ErrorKind::Other,
                            format!(
                                "Tungstenite Close Error: {:?}: {}",
                                close_frame.code, close_frame.reason
                            ),
                        ))),

                        _ => Poll::Ready(Ok(())),
                    }
                }

                // Ignore other websocket messages
                _ => Poll::Pending,
            },
        }
    }
}

/// Implements a streaming write interface over a websocket client. Each write
/// is sent to the server as a Binary message. No write-buffering is performed.
impl AsyncWrite for TungsteniteSerialStream {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<Result<usize, std::io::Error>> {
        let self_ = self.get_mut();

        // Prepare the websocket
        let wss_was_prepared = ready!(Pin::new(&mut self_.wss).poll_ready(cx));

        Poll::Ready(
            wss_was_prepared
                .and_then(|_| {
                    // Write a binary message with the buf as the data
                    Pin::new(&mut self_.wss)
                        .start_send(tokio_tungstenite::tungstenite::Message::Binary(
                            buf.to_vec(),
                        ))
                        .map(|_| buf.len())
                })
                .map_err(tf_tungstenite_err_into_stdio),
        )
    }

    fn poll_flush(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), std::io::Error>> {
        Pin::new(&mut self.get_mut().wss)
            .poll_flush(cx)
            .map_err(tf_tungstenite_err_into_stdio)
    }

    fn poll_shutdown(
        self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), std::io::Error>> {
        Pin::new(&mut self.get_mut().wss)
            .poll_close(cx)
            .map_err(tf_tungstenite_err_into_stdio)
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: SerBridgeHostCmd = argh::from_env();

    let mut stream: Pin<Box<dyn ICanReadAndWriteWhichNobodyExpected>> = match args.subcmd {
        SerBridgeHostSubCmd::Unix(cmd) => {
            let stream = UnixStream::connect(&cmd.vm_serial).await?;

            Box::pin(BufStream::new(stream))
        }
        SerBridgeHostSubCmd::Rack(cmd) => {
            let base = cmd.rack_addr.as_str();

            // YYY hax
            let token = {
                let hosts_toml = std::fs::read_to_string("/home/vi/.config/oxide/hosts.toml")?;
                let token_ln = hosts_toml
                    .lines()
                    .filter(|ln| ln.starts_with("token ="))
                    .next()
                    .unwrap();
                token_ln.replace("\"", "").replace("token = ", "")
            };

            let ox_client = oxide::Client::new_with_auth_token(base, &token);

            // Make sure that we can view the instance because the
            // `instance_serial_console_stream` doesn't handle/report API errors.
            // So this should handle things like
            // - auth errors
            // - instance doesnt exist
            // - instance is offline
            let instance = ox_client
                .instance_view()
                .instance(&cmd.instance)
                .send()
                .await?;

            if instance.run_state != InstanceState::Running {
                bail!(
                    "Instance is not running, it is instead {:?}",
                    instance.run_state
                );
            }

            let response = ox_client
                .instance_serial_console_stream()
                .instance(&cmd.instance)
                .most_recent(1024 * 1024)
                .send()
                .await
                .map_err(|e| e.into_untyped())?
                .into_inner();

            let wss = tokio_tungstenite::WebSocketStream::from_raw_socket(
                response,
                tokio_tungstenite::tungstenite::protocol::Role::Client,
                None,
            )
            .await;
            Box::pin(TungsteniteSerialStream {
                wss,
                msg_buf: Vec::new(),
            })
        }
    };

    let job = args.job.clone();

    let mut stdout = io::stdout();

    loop {
        let msg = receive_message(&mut stream).await?;
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
                    &mut stream,
                    &HostToGuestMsg::PleaseRunTheseTests(job.clone()),
                )
                .await?
            }
            GuestToHostMsg::Done() => break,
        }
    }

    Ok(())
}
