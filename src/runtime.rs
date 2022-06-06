use std::collections::HashMap;
#[cfg(test)]
use std::rc::Rc;

use crate::object::Object;
use crate::runtime_error::RuntimeError;
use crate::store::Store;
#[cfg(test)]
use crate::store::StoredObject;
use crate::vocabulary::{Vocabularies, Vocabulary};
use crate::word::{Word, WordResult};

pub struct Runtime {
    pub store: Store,
    pub vocabularies: Vocabularies,
}

impl Runtime {
    pub fn feed_word(&mut self, written: &str) -> Result<(), RuntimeError> {
        Ok(())
    }
}

impl Default for Runtime {
    fn default() -> Self {
        let store = Store::default();
        // TODO: impl Default for Dictionary instead (needs refactor of Dictionary to be a wrapper
        // type instead of alias)
        let mut primitives_dictionary = Vocabulary::new_named("__@PRIMITIVES");

        populate_primitive_words(&mut primitives_dictionary)
            .expect("internal error populating primitive words");

        Self {
            store,
            vocabularies: {
                let mut vocabs = HashMap::with_capacity(crate::DEFAULT_VOCABULARIES_CAPACITY);
                vocabs.insert(primitives_dictionary.name.clone(), primitives_dictionary);
                Vocabularies(vocabs)
            },
        }
    }
}

fn populate_primitive_words(voc: &mut Vocabulary) -> Result<(), RuntimeError> {
    // stack ops
    voc.define_word("__@DROP", Word::PrimitiveImplementation(prim_word_drop))?;
    voc.define_word("__@DUP", Word::PrimitiveImplementation(prim_word_dup))?;
    voc.define_word("__@SWAP", Word::PrimitiveImplementation(prim_word_swap))?;

    // math
    voc.define_word("__@ADD", Word::PrimitiveImplementation(prim_word_add))?;
    voc.define_word("__@SUB", Word::PrimitiveImplementation(prim_word_sub))?;
    voc.define_word("__@MUL", Word::PrimitiveImplementation(prim_word_mul))?;
    voc.define_word("__@DIV", Word::PrimitiveImplementation(prim_word_div))?;
    //voc.define_word("__@MOD", Word::PrimitiveImplementation(prim_word_mod))?;

    Ok(())
}

fn prim_word_swap(rt: &mut Runtime) -> WordResult {
    rt.store.swap()?;
    Ok(())
}

fn prim_word_dup(rt: &mut Runtime) -> WordResult {
    rt.store.dup()?;
    Ok(())
}

// Drop is just a Pop where we don't care about the return value
fn prim_word_drop(rt: &mut Runtime) -> WordResult {
    rt.store.pop()?;
    Ok(())
}

fn prim_word_add(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let right = rt.store.pop()?;
    let left = rt.store.pop()?;

    rt.store
        .push(match (&*left, &*right) {
            (Object::SignedInt(l), Object::SignedInt(r)) => Ok(Object::SignedInt(l + r)),
            (Object::UnsignedInt(l), Object::UnsignedInt(r)) => Ok(Object::UnsignedInt(l + r)),
            (Object::Float32(l), Object::Float32(r)) => Ok(Object::Float32(l + r)),
            (Object::Float64(l), Object::Float64(r)) => Ok(Object::Float64(l + r)),

            (_, _) => Err(RuntimeError::IncompatibleTypes),
        }?)
        .map(|_| ())
}

fn prim_word_sub(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let to_subtract = rt.store.pop()?;
    let subtract_from = rt.store.pop()?;

    rt.store
        .push(match (&*subtract_from, &*to_subtract) {
            (Object::SignedInt(sf), Object::SignedInt(ts)) => Ok(Object::SignedInt(sf - ts)),
            (Object::UnsignedInt(sf), Object::UnsignedInt(ts)) => Ok(Object::UnsignedInt(sf - ts)),
            (Object::Float32(sf), Object::Float32(ts)) => Ok(Object::Float32(sf - ts)),
            (Object::Float64(sf), Object::Float64(ts)) => Ok(Object::Float64(sf - ts)),

            (_, _) => Err(RuntimeError::IncompatibleTypes),
        }?)
        .map(|_| ())
}

fn prim_word_mul(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let right = rt.store.pop()?;
    let left = rt.store.pop()?;

    rt.store
        .push(match (&*left, &*right) {
            (Object::SignedInt(l), Object::SignedInt(r)) => Ok(Object::SignedInt(l * r)),
            (Object::UnsignedInt(l), Object::UnsignedInt(r)) => Ok(Object::UnsignedInt(l * r)),
            (Object::Float32(l), Object::Float32(r)) => Ok(Object::Float32(l * r)),
            (Object::Float64(l), Object::Float64(r)) => Ok(Object::Float64(l * r)),

            (_, _) => Err(RuntimeError::IncompatibleTypes),
        }?)
        .map(|_| ())
}

fn prim_word_div(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let divisor = rt.store.pop()?;
    let dividend = rt.store.pop()?;

    rt.store
        .push(match (&*dividend, &*divisor) {
            // divide by zero returns a DivideByZero error further up the stack; if we end up
            // here, something is broken with the type system
            (_, Object::SignedInt(0) | Object::UnsignedInt(0)) => {
                unreachable!("type system allowed division by zero")
            }
            (_, Object::Float32(x)) if x.eq(&0.0) => {
                unreachable!("type system allowed division by zero")
            }
            (_, Object::Float64(x)) if x.eq(&0.0) => {
                unreachable!("type system allowed division by zero")
            }

            (Object::SignedInt(dend), Object::SignedInt(dsor)) => {
                Ok(Object::SignedInt(dend / dsor))
            }
            (Object::UnsignedInt(dend), Object::UnsignedInt(dsor)) => {
                Ok(Object::UnsignedInt(dend / dsor))
            }
            (Object::Float32(dend), Object::Float32(dsor)) => Ok(Object::Float32(dend / dsor)),
            (Object::Float64(dend), Object::Float64(dsor)) => Ok(Object::Float64(dend / dsor)),

            (_, _) => Err(RuntimeError::IncompatibleTypes),
        }?)
        .map(|_| ())
}

// fn prim_word_mod(rt: &mut Runtime) -> WordResult {
//     if rt.store.len() < 2 {
//         return Err(RuntimeError::StackUnderflow);
//     }
//
//     let left = rt.store.pop()?;
//     let right = rt.store.pop()?;
//
//     Ok(())
// }

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_store_empty(store: &Store) {
        assert_eq!(store.len(), 0);
    }

    fn push_uint_to_stack(store: &mut Store, val: usize) -> Result<&StoredObject, RuntimeError> {
        store.push(Object::UnsignedInt(val))
    }

    fn push_int_to_stack(store: &mut Store, val: isize) -> Result<&StoredObject, RuntimeError> {
        store.push(Object::SignedInt(val))
    }

    fn push_f32_to_stack(store: &mut Store, val: f32) -> Result<&StoredObject, RuntimeError> {
        store.push(Object::Float32(val))
    }

    fn push_f64_to_stack(store: &mut Store, val: f64) -> Result<&StoredObject, RuntimeError> {
        store.push(Object::Float64(val))
    }

    #[test]
    fn test_swap() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        push_uint_to_stack(&mut runtime.store, 1)?;
        push_uint_to_stack(&mut runtime.store, 2)?;
        prim_word_swap(&mut runtime)?;
        assert_eq!(
            Rc::try_unwrap(runtime.store.pop()?),
            Ok(Object::UnsignedInt(1)),
        );
        assert_eq!(
            Rc::try_unwrap(runtime.store.pop()?),
            Ok(Object::UnsignedInt(2)),
        );

        Ok(())
    }

    #[test]
    fn test_dup() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        push_uint_to_stack(&mut runtime.store, 1)?;
        prim_word_dup(&mut runtime)?;
        let top = runtime.store.pop()?;
        let second = runtime.store.pop()?;

        // dup will always share memory (remember that gluumy is immutable
        // at its core!)
        assert!(Rc::ptr_eq(&top, &second));

        // now we know we can safely just discard the top entry: using
        // try_unwrap on this to pattern match the underlying object will
        // fail anyway since the strong_count is > 1
        drop(top);

        assert_eq!(Rc::strong_count(&second), 1);
        assert_eq!(Rc::try_unwrap(second), Ok(Object::UnsignedInt(1)));

        Ok(())
    }

    #[test]
    fn test_drop() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);
        push_uint_to_stack(&mut runtime.store, 1)?;
        prim_word_drop(&mut runtime)?;
        assert_store_empty(&runtime.store);

        Ok(())
    }

    #[test]
    fn test_mul_underflow() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();
        assert_eq!(
            prim_word_mul(&mut runtime),
            Err(RuntimeError::StackUnderflow),
        );
        push_uint_to_stack(&mut runtime.store, 1)?;
        assert_eq!(
            prim_word_mul(&mut runtime),
            Err(RuntimeError::StackUnderflow),
        );
        Ok(())
    }

    #[test]
    fn test_mul_uints() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        push_uint_to_stack(&mut runtime.store, 2)?;
        push_uint_to_stack(&mut runtime.store, 2)?;
        prim_word_mul(&mut runtime)?;

        assert_eq!(
            Rc::try_unwrap(runtime.store.pop()?),
            Ok(Object::UnsignedInt(4)),
        );

        assert_store_empty(&runtime.store);

        Ok(())
    }

    #[test]
    fn test_mul_iints() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        push_int_to_stack(&mut runtime.store, 2)?;
        push_int_to_stack(&mut runtime.store, 2)?;
        prim_word_mul(&mut runtime)?;

        assert_eq!(
            Rc::try_unwrap(runtime.store.pop()?),
            Ok(Object::SignedInt(4)),
        );

        assert_store_empty(&runtime.store);

        Ok(())
    }

    #[test]
    // NOTE: this test may be blippy if float math does what float math likes to do and returns,
    // say, 3.9999999999999999. may be worth building a bunch of deconstructor methods to access
    // the inner float of a Primitive, rounding it to the nearest int, and comparing to usize(4)
    // here instead
    fn test_mul_floats() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        push_f64_to_stack(&mut runtime.store, 2.0)?;
        push_f64_to_stack(&mut runtime.store, 2.0)?;
        prim_word_mul(&mut runtime)?;

        assert_eq!(
            Rc::try_unwrap(runtime.store.pop()?),
            Ok(Object::Float64(4.0))
        );

        assert_store_empty(&runtime.store);

        Ok(())
    }
}
