use std::fmt::{self, Display, Formatter};

use crate::runtime::Runtime;
use crate::runtime_error::RuntimeError;

pub type PrimitiveImplementation = fn(&mut Runtime) -> WordResult;
pub type WordResult = Result<(), RuntimeError>;

#[derive(Clone)]
pub enum Word {
    PrimitiveImplementation(PrimitiveImplementation),
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
