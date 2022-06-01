use std::collections::HashMap;
use std::rc::Rc;

use crate::object::Object;
use crate::runtime_error::RuntimeError;
use crate::store::Store;
use crate::vocabulary::{Vocabularies, Vocabulary};
use crate::word::{Word, WordResult};

pub struct Runtime<'rt> {
    pub store: Store,
    pub vocabularies: Vocabularies<'rt>,
    pub current_vocabularies: [bool; crate::MAX_SIMULTANEOUS_VOCABULARIES],
    pub vocabulary_index: HashMap<Rc<String>, usize>,
}

impl Runtime<'_> {
    pub fn feed_word(&mut self, written: &str) -> Result<(), RuntimeError> {
        Ok(())
    }
}

impl Default for Runtime<'_> {
    fn default() -> Self {
        let store = Store::default();
        // TODO: impl Default for Dictionary instead (needs refactor of Dictionary to be a wrapper
        // type instead of alias)
        let mut primitives_dictionary = Vocabulary::new_named("__@PRIMITIVES");

        populate_primitive_words(&mut primitives_dictionary)
            .expect("internal error populating primitive words");

        Self {
            store,
            vocabularies: Vocabularies::new_with_primitives(primitives_dictionary),
            current_vocabularies: [false; crate::MAX_SIMULTANEOUS_VOCABULARIES],
            vocabulary_index: {
                let hm = HashMap::with_capacity(crate::MAX_SIMULTANEOUS_VOCABULARIES);
                hm.insert(primitives_dictionary.name.clone(), 0);
                hm
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

    rt.store.push(match (*left, *right) {
        (Object::SignedInt(l), Object::SignedInt(r)) => Ok(Object::SignedInt(l + r)),
        (Object::UnsignedInt(l), Object::UnsignedInt(r)) => Ok(Object::UnsignedInt(l + r)),
        (Object::Float32(l), Object::Float32(r)) => Ok(Object::Float32(l + r)),
        (Object::Float32(l), Object::Float64(r)) => Ok(Object::Float64(l as f64 + r)),
        (Object::Float64(l), Object::Float32(r)) => Ok(Object::Float64(l + r as f64)),
        (Object::Float64(l), Object::Float64(r)) => Ok(Object::Float64(l + r)),

        (_, _) => Err(RuntimeError::IncompatibleTypes),
    }?);

    Ok(())
}

fn prim_word_sub(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let to_subtract = rt.store.pop()?;
    let subtract_from = rt.store.pop()?;

    rt.store.push(match (*subtract_from, *to_subtract) {
        (Object::SignedInt(sf), Object::SignedInt(ts)) => Ok(Object::SignedInt(sf - ts)),
        (Object::UnsignedInt(sf), Object::UnsignedInt(ts)) => Ok(Object::UnsignedInt(sf - ts)),
        (Object::Float32(sf), Object::Float32(ts)) => Ok(Object::Float32(sf - ts)),
        (Object::Float32(sf), Object::Float64(ts)) => Ok(Object::Float64(sf as f64 - ts)),
        (Object::Float64(sf), Object::Float32(ts)) => Ok(Object::Float64(sf - ts as f64)),
        (Object::Float64(sf), Object::Float64(ts)) => Ok(Object::Float64(sf - ts)),

        (_, _) => Err(RuntimeError::IncompatibleTypes),
    }?);

    Ok(())
}

fn prim_word_mul(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let right = rt.store.pop()?;
    let left = rt.store.pop()?;

    rt.store.push(match (*left, *right) {
        (Object::SignedInt(l), Object::SignedInt(r)) => Ok(Object::SignedInt(l * r)),
        (Object::UnsignedInt(l), Object::UnsignedInt(r)) => Ok(Object::UnsignedInt(l * r)),
        (Object::Float32(l), Object::Float32(r)) => Ok(Object::Float32(l * r)),
        (Object::Float32(l), Object::Float64(r)) => Ok(Object::Float64(l as f64 * r)),
        (Object::Float64(l), Object::Float32(r)) => Ok(Object::Float64(l * r as f64)),
        (Object::Float64(l), Object::Float64(r)) => Ok(Object::Float64(l * r)),

        (_, _) => Err(RuntimeError::IncompatibleTypes),
    }?);
    Ok(())
}

fn prim_word_div(rt: &mut Runtime) -> WordResult {
    if rt.store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let divisor = rt.store.pop()?;
    let dividend = rt.store.pop()?;

    rt.store.push(match (*dividend, *divisor) {
        // divide by zero returns a DivideByZero error further up the stack; if we end up
        // here, something is broken with the type system
        (
            _,
            Object::SignedInt(0)
            | Object::UnsignedInt(0)
            | Object::Float32(0.0)
            | Object::Float64(0.0),
        ) => unreachable!("type system allowed division by zero"),

        (Object::SignedInt(dend), Object::SignedInt(dsor)) => Ok(Object::SignedInt(dend / dsor)),
        (Object::UnsignedInt(dend), Object::UnsignedInt(dsor)) => {
            Ok(Object::UnsignedInt(dend / dsor))
        }
        (Object::Float32(dend), Object::Float32(dsor)) => Ok(Object::Float32(dend / dsor)),
        (Object::Float32(dend), Object::Float64(dsor)) => Ok(Object::Float64(dend as f64 / dsor)),
        (Object::Float64(dend), Object::Float32(dsor)) => Ok(Object::Float64(dend / dsor as f64)),
        (Object::Float64(dend), Object::Float64(dsor)) => Ok(Object::Float64(dend / dsor)),

        (_, _) => Err(RuntimeError::IncompatibleTypes),
    }?);

    Ok(())
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

    fn push_uint_to_stack(store: &mut Store, val: usize) {
        store.push(StoreEntry(Object::Primitive(Primitive::UnsignedInt(val))))
    }

    fn push_int_to_stack(store: &mut Store, val: isize) {
        store.push(StoreEntry(Object::Primitive(Primitive::SignedInt(val))))
    }

    fn push_float_to_stack(store: &mut Store, val: StandardFloat) {
        store.push(StoreEntry(Object::Primitive(Primitive::Float(val))))
    }

    #[test]
    fn test_swap() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        push_uint_to_stack(&mut runtime.store, 1);
        push_uint_to_stack(&mut runtime.store, 2);
        runtime.feed_word("swap")?;
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(2))),
        );

        Ok(())
    }

    #[test]
    fn test_dup() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        push_uint_to_stack(&mut runtime.store, 1);
        runtime.feed_word("dup")?;
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );

        Ok(())
    }

    #[test]
    fn test_drop() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);
        push_uint_to_stack(&mut runtime.store, 1);
        runtime.feed_word("drop")?;
        assert_store_empty(&runtime.store);

        Ok(())
    }

    #[test]
    fn test_str_literal() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        runtime.feed_word("\"hello world\"")?;
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::String("hello world".into()))),
        );

        Ok(())
    }

    #[test]
    fn test_uint_literal() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        runtime.feed_word("1")?;
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );

        runtime.feed_word("1")?;
        runtime.feed_word("2")?;
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(2))),
        );

        Ok(())
    }

    #[test]
    fn test_iint_literal() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        runtime.feed_word("-1")?;
        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::SignedInt(-1))),
        );

        Ok(())
    }

    #[test]
    fn test_mul_underflow() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();
        assert_eq!(
            prim_word_mul(&mut runtime.store),
            Err(RuntimeError::StackUnderflow),
        );
        push_uint_to_stack(&mut runtime.store, 1);
        assert_eq!(
            prim_word_mul(&mut runtime.store),
            Err(RuntimeError::StackUnderflow),
        );
        Ok(())
    }

    #[test]
    fn test_mul_uints() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        push_uint_to_stack(&mut runtime.store, 2);
        push_uint_to_stack(&mut runtime.store, 2);
        prim_word_mul(&mut runtime.store)?;

        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(4)),),
        );

        assert_store_empty(&runtime.store);

        Ok(())
    }

    #[test]
    fn test_mul_iints() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        push_int_to_stack(&mut runtime.store, 2);
        push_int_to_stack(&mut runtime.store, 2);
        prim_word_mul(&mut runtime.store)?;

        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::SignedInt(4)),),
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

        push_float_to_stack(&mut runtime.store, 2.0);
        push_float_to_stack(&mut runtime.store, 2.0);
        prim_word_mul(&mut runtime.store)?;

        assert_eq!(
            runtime.store.pop()?,
            StoreEntry(Object::Primitive(Primitive::Float(4.0)),),
        );

        assert_store_empty(&runtime.store);

        Ok(())
    }
}
