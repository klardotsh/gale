use std::fmt::{self, Display};

#[derive(Clone, Debug, PartialEq)]
pub struct TypeSignature {
    pub shape_id: usize,
    pub subshape_id: Option<usize>,
    pub name: String,

    last_subshape_id: Option<usize>,
}

impl TypeSignature {
    // TODO return a proper error enum
    pub fn new_subshape(&self, name: String) -> Result<TypeSignature, String> {
        match self.subshape_id {
            Some(_) => Err("can't create subshape of a subshape".into()),
            None => Ok(TypeSignature {
                name,
                shape_id: self.shape_id,
                subshape_id: Some(self.next_subshape_id()),
                last_subshape_id: None,
            }),
        }
    }

    fn next_subshape_id(&mut self) -> usize {
        self.last_subshape_id = self
            .last_subshape_id
            .and_then(|last_subshape_id| Some(last_subshape_id + 1))
            .or(Some(0));
        self.last_subshape_id.unwrap_unchecked()
    }
}

impl Display for TypeSignature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "?")
    }
}
