use std::io::Error as IOError;

#[derive(Clone, Debug, PartialEq)]
pub enum InternalError {
    // TODO: see if there's a better way to store this than just stringifying it; io::Error does
    // not implement PartialEq due to a Custom error kind in the return set
    IOError(String),

    WordInsertionFailed,
}

impl From<IOError> for InternalError {
    fn from(src: IOError) -> Self {
        Self::IOError(src.to_string())
    }
}
