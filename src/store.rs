use crate::object::Object;
use crate::runtime_error::RuntimeError;

use std::fmt::{self, Display};
use std::rc::Rc;

pub type StoredObject = Rc<Object>;

// frankly arbitrary for now
pub const DEFAULT_STORE_CAPACITY: usize = 4096;

// TODO: general note for the future: Rust is working on allocator APIs
// which would allow us to properly catch "stack overflows" (alloc
// failures) here. Not entirely sure whether there's actual UX
// improvements to be found there in most cases: a SO in a REPL is maybe
// useful to be able to continue onwards from, but an SO in most other
// running applications is almost certainly going to be fatal anyway,
// and just noise for a developer to have to explicitly handle in 90%+
// of desktop usecases.
pub struct Store(Vec<StoredObject>);

impl Store {
    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn push(&mut self, item: Object) -> Result<&StoredObject, RuntimeError> {
        self.0.push(StoredObject::new(item));
        self.peek()
    }

    pub fn push_boxed(&mut self, item: StoredObject) -> Result<&StoredObject, RuntimeError> {
        self.0.push(item);
        self.peek()
    }

    pub fn pop(&mut self) -> Result<StoredObject, RuntimeError> {
        self.0.pop().ok_or(RuntimeError::StackUnderflow)
    }

    /// Returns a reference to the top object on the stack.
    pub fn peek(&self) -> Result<&StoredObject, RuntimeError> {
        self.npeek(0)
    }

    /// Returns a reference to the nth object on the stack, where 0 is the top.
    pub fn npeek(&self, n: usize) -> Result<&StoredObject, RuntimeError> {
        self.0
            .get(self.0.len() - 1 - n)
            .ok_or(RuntimeError::StackUnderflow)
    }

    /// Returns a reference to the top object on the stack.
    pub fn dup(&mut self) -> Result<&StoredObject, RuntimeError> {
        self.push_boxed(self.peek()?.clone())
    }

    /// Returns references to the now-second and first items on the stack, in that order.
    pub fn swap(&mut self) -> Result<(&StoredObject, &StoredObject), RuntimeError> {
        // normally "ask forgiveness and not permission" applies, but since pop()
        // mutates state, let's do the barely-slower thing and ask permission
        // this time, by npeek-ing the second object on the stack as a way of
        // detecting underflows
        self.npeek(1)?;
        let old_top = self.pop()?;
        let old_second = self.pop()?;
        self.push_boxed(old_top)?;
        self.push_boxed(old_second)?;

        // TODO: implement some peek_unchecked methods much like how rust
        // stdlib does, for perf. should also use them in methods like push
        Ok((self.npeek(1)?, self.peek()?))
    }

    /// Moves the third item (from the top) of the stack to the top, pushing the next two items
    /// down.
    ///
    /// Returns references to the now-third, second, and first items on the stack, in that order.
    pub fn rot(&mut self) -> Result<(&StoredObject, &StoredObject, &StoredObject), RuntimeError> {
        // normally "ask forgiveness and not permission" applies, but since pop()
        // mutates state, let's do the barely-slower thing and ask permission
        // this time, by npeek-ing the third object on the stack as a way of
        // detecting underflows
        self.npeek(2)?;
        let old_top = self.pop()?;
        let old_second = self.pop()?;
        let old_third = self.pop()?;
        self.push_boxed(old_second)?;
        self.push_boxed(old_top)?;
        self.push_boxed(old_third)?;

        // TODO: implement some peek_unchecked methods much like how rust
        // stdlib does, for perf. should also use them in methods like push
        Ok((self.npeek(2)?, self.npeek(1)?, self.peek()?))
    }
}

impl Default for Store {
    fn default() -> Self {
        Self(Vec::with_capacity(DEFAULT_STORE_CAPACITY))
    }
}

impl Display for Store {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Store[ ")?;

        for entry in &self.0 {
            write!(f, "{}, ", entry.to_string())?;
        }

        write!(f, "]")?;

        Ok(())
    }
}
