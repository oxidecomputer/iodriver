// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const ALIGNMENT_SEQUENCE: &[u8] = "==\"'= ALIGNMENT SEQUENCE - SOLSTICE =\"'==".as_bytes();

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
    TestOutput(TestOutput),
    Done(),
}
