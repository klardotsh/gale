use std::fmt::{self, Display};

#[derive(Clone, Debug, PartialEq)]
pub struct TypeSignature {
    pub shape_id: usize,
    pub subshape_id: Option<usize>,
    pub name: String,
}

impl Display for TypeSignature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "?")
    }
}
