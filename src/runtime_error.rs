use std::io::{self};

#[derive(Clone, Debug, PartialEq)]
pub enum RuntimeError {
    //InternalError(InternalError),
    StackUnderflow,
    StackOverflow,
    IncompatibleTypes,
    NoWordsByName(String),
}

/*
impl From<io::Error> for RuntimeError {
    fn from(src: io::Error) -> Self {
        Self::InternalError(src.into())
    }
}
*/
