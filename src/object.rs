use std::fmt::{self, Display};

use crate::vocabulary::Vocabulary;
use crate::word::Word;

#[derive(Clone)]
pub enum Object {
    Vocabulary(Vocabulary),
    Word(Word),

    SignedInt(isize),
    UnsignedInt(usize),
    Float32(f32),
    Float64(f64),
}

impl Display for Object {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self)
    }
}
