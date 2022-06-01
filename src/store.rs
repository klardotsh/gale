use crate::object::Object;
use crate::runtime_error::RuntimeError;

use std::fmt::{self, Display};
use std::rc::Rc;

const MAX_STORE_SIZE: usize = 4096; // arbitrary for now

pub type StoredObject = Rc<Object>;

pub struct Store {
    stack: [Option<StoredObject>; MAX_STORE_SIZE],
    next_idx: usize,
}

impl Store {
    pub fn len(&self) -> usize {
        self.stack.len()
    }

    pub fn push(&mut self, item: Object) -> Result<&StoredObject, RuntimeError> {
        if self.next_idx > MAX_STORE_SIZE - 1 {
            return Err(RuntimeError::StackOverflow);
        }
        self.stack[self.next_idx] = Some(StoredObject::new(item));
        self.next_idx += 1;
        Ok(self.stack[self.next_idx - 1].as_ref().unwrap())
    }

    pub fn pop(&mut self) -> Result<StoredObject, RuntimeError> {
        if self.next_idx == 0 {
            return Err(RuntimeError::StackUnderflow);
        }
        self.next_idx -= 1;
        let top = self.stack[self.next_idx].unwrap();
        self.stack[self.next_idx] = None;
        Ok(top)
    }

    /// Returns a reference to the top object on the stack.
    pub fn peek(&self) -> Result<&StoredObject, RuntimeError> {
        self.npeek(0)
    }

    /// Returns a reference to the nth object on the stack, where 0 is the top.
    pub fn npeek(&mut self, n: usize) -> Result<&StoredObject, RuntimeError> {
        if self.next_idx == n {
            return Err(RuntimeError::StackUnderflow);
        }
        Ok(self.stack[self.next_idx + n - 1].as_ref().unwrap())
    }

    /// Returns references to the now-second and first items on the stack, in that order.
    pub fn dup(&mut self) -> Result<(&StoredObject, &StoredObject), RuntimeError> {
        if self.next_idx == 0 {
            return Err(RuntimeError::StackUnderflow);
        }
        self.stack[self.next_idx] = self.stack[self.next_idx - 1].clone();
        self.next_idx += 1;
        Ok((
            self.stack[self.next_idx - 2].as_ref().unwrap(),
            self.stack[self.next_idx - 1].as_ref().unwrap(),
        ))
    }

    /// Returns references to the now-second and first items on the stack, in that order.
    pub fn swap(&mut self) -> Result<(&StoredObject, &StoredObject), RuntimeError> {
        if self.next_idx == 1 {
            return Err(RuntimeError::StackUnderflow);
        }

        let old_i = self.stack[self.next_idx - 2];
        let old_j = self.stack[self.next_idx - 1];
        self.stack[self.next_idx - 1] = old_i;
        self.stack[self.next_idx - 2] = old_j;

        Ok((old_j.as_ref().unwrap(), old_i.as_ref().unwrap()))
    }

    /// Moves the third item (from the top) of the stack to the top, pushing the next two items
    /// down.
    ///
    /// Returns references to the now-third, second, and first items on the stack, in that order.
    pub fn rot(&mut self) -> Result<(&StoredObject, &StoredObject, &StoredObject), RuntimeError> {
        if self.next_idx == 2 {
            return Err(RuntimeError::StackUnderflow);
        }

        let old_i = self.stack[self.next_idx - 3];
        let old_j = self.stack[self.next_idx - 2];
        let old_k = self.stack[self.next_idx - 1];
        self.stack[self.next_idx - 1] = old_i;
        self.stack[self.next_idx - 2] = old_k;
        self.stack[self.next_idx - 3] = old_j;

        Ok((
            old_j.as_ref().unwrap(),
            old_k.as_ref().unwrap(),
            old_i.as_ref().unwrap(),
        ))
    }
}

impl Default for Store {
    fn default() -> Self {
        Self {
            stack: [None; MAX_STORE_SIZE],
            next_idx: 0,
        }
    }
}

impl Display for Store {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Store[ ")?;

        for entry in &self.stack {
            write!(
                f,
                "{}, ",
                match entry {
                    None => "(missing)",
                    Some(obj) => &obj.to_string(),
                }
            )?;
        }

        write!(f, "]")?;

        Ok(())
    }
}
