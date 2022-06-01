use std::io::Error as IOError;

use crate::internal_error::InternalError;

#[derive(Clone, Debug, PartialEq)]
pub enum RuntimeError {
    InternalError(InternalError),
    StackUnderflow,
    StackOverflow,
    IncompatibleTypes,
    NoWordsByName(String),
}

impl From<IOError> for RuntimeError {
    fn from(src: IOError) -> Self {
        Self::InternalError(src.into())
    }
}
