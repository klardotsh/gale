use crate::runtime_error::RuntimeError;

use std::fmt::{self, Display};

const MAX_STORE_SIZE: usize = 4096; // arbitrary for now

#[derive(Clone, Debug, PartialEq)]
struct StoreEntry(Object);

pub struct Store {
    stack: [StoreEntry; MAX_STORE_SIZE],
    next_idx: usize,
}

impl Store {
    fn len(&self) -> usize {
        self.stack.len()
    }

    fn push(&mut self, item: StoreEntry) -> Result<&StoreEntry, RuntimeError> {
        if self.next_idx > MAX_STORE_SIZE - 1 {
            return Err(RuntimeError::StackOverflow)
        }
        self.stack[self.next_idx] = item;
        self.next_idx += 1;
        Ok(&self.stack[self.next_idx - 1])
    }

    fn pop(&mut self) -> Result<&StoreEntry, RuntimeError> {
        if self.next_idx == 0 {
            return Err(RuntimeError::StackUnderflow)
        }
        self.next_idx -= 1;
        Ok(&self.stack[self.next_idx])
    }

    /// Returns references to the now-second and first items on the stack, in that order.
    fn dup(&mut self) -> Result<(&StoreEntry, &StoreEntry), RuntimeError> {
        if self.next_idx == 0 {
            return Err(RuntimeError::StackUnderflow)
        }
        self.stack[self.next_idx] = self.stack[self.next_idx - 1];
        self.next_idx += 1;
        Ok((&self.stack[self.next_idx - 2], &self.stack[self.next_idx - 1]))
    }

    /// Returns references to the now-second and first items on the stack, in that order.
    fn swap(&mut self) -> Result<(&StoreEntry, &StoreEntry), RuntimeError> {
        if self.next_idx == 1 {
            return Err(RuntimeError::StackUnderflow)
        }

        let old_i = self.stack[self.next_idx - 2];
        let old_j = self.stack[self.next_idx - 1];
        self.stack[self.next_idx - 1] = old_i;
        self.stack[self.next_idx - 2] = old_j;

        Ok((&old_j, &old_i))
    }

    /// Moves the third item (from the top) of the stack to the top, pushing the next two items
    /// down.
    ///
    /// Returns references to the now-third, second, and first items on the stack, in that order.
    fn rot(&mut self) -> Result<(&StoreEntry, &StoreEntry, &StoreEntry), RuntimeError> {
        if self.next_idx == 2 {
            return Err(RuntimeError::StackUnderflow)
        }

        let old_i = self.stack[self.next_idx - 3];
        let old_j = self.stack[self.next_idx - 2];
        let old_k = self.stack[self.next_idx - 1];
        self.stack[self.next_idx - 1] = old_i;
        self.stack[self.next_idx - 2] = old_k;
        self.stack[self.next_idx - 3] = old_j;

        Ok((&old_j, &old_k, &old_i))
    }
}

impl Default for Store {
    fn default() -> Self {
        Self {
            stack: [Object::default(); MAX_STORE_SIZE],
            next_idx: 0,
        }
    }
}

impl Display for Store {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Store[ ")?;

        for entry in &self.stack {
            write!(f, "{}, ", entry)?;
        }

        write!(f, "]")?;

        Ok(())
    }
}

