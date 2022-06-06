use std::fmt::{self, Display, Formatter};

use crate::runtime::Runtime;
use crate::runtime_error::RuntimeError;

pub type PrimitiveImplementation = fn(&mut Runtime) -> WordResult;
pub type WordResult = Result<(), RuntimeError>;

#[derive(Clone)]
pub enum Word {
    PrimitiveImplementation(PrimitiveImplementation),
}

impl fmt::Debug for Word {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> Result<(), fmt::Error> {
        match self {
            Word::PrimitiveImplementation(_) => Display::fmt(self, formatter),
        }
    }
}

impl Display for Word {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> Result<(), fmt::Error> {
        write!(
            formatter,
            "{}",
            match self {
                Self::PrimitiveImplementation(_) => "(primitive word)",
            }
        )
    }
}

impl PartialEq for Word {
    fn eq(&self, _: &Self) -> bool {
        // for now, naively claim no two primitives are the same, which frankly
        // may be a permanent and non-naive assertion anyway
        false
    }
}
