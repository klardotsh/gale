// gluumy: a hackable, type-safe, minimalist, stack-based programming language
//
// (it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase, always)
//
//  _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
// (_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
//        _|                 /           _|                   _|

mod runtime_error;
mod store;

use runtime_error::RuntimeError;
use store::Store;

use std::collections::HashMap;
use std::fmt::{self, Display};
use std::io::{self, BufRead};
use std::ops::{Deref, DerefMut};

const MAX_SIMULTANEOUS_VOCABULARIES: usize = 25;

const DEFAULT_DICTIONARY_CAPACITY_WORDS: usize = 1024;
const DEFAULT_DICTIONARY_CAPACITY_PER_WORD: usize = 3;

const WORD_SPLITTING_CHARS: [char; 3] = [' ', '\t', '\n'];

type StandardFloat = f64;
type WordResult = Result<(), RuntimeError>;
type PrimitiveImplementation = fn(&mut Store) -> WordResult;

#[derive(Clone)]
struct Vocabularies<'rt>(HashMap<&'rt str, Vocabulary>);

#[derive(Clone)]
struct Vocabulary(HashMap<String, Word>);

#[derive(Clone)]
enum Word {
    PrimitiveImplementation(PrimitiveImplementation),
}

#[derive(Clone, Debug, PartialEq)]
enum InternalError {
    // TODO: see if there's a better way to store this than just stringifying it; io::Error does
    // not implement PartialEq due to a Custom error kind in the return set
    IOError(String),

    WordInsertionFailed,
}

impl From<io::Error> for InternalError {
    fn from(src: io::Error) -> Self {
        Self::IOError(src.to_string())
    }
}

struct Runtime<'rt> {
    store: Store,
    vocabularies: Vocabularies<'rt>,
    current_vocabularies: [&'rt Vocabulary; MAX_SIMULTANEOUS_VOCABULARIES],
}

impl Runtime<'_> {
}

impl Default for Runtime<'_> {
    fn default() -> Self {
        let store = Store::default();
        // TODO: impl Default for Dictionary instead (needs refactor of Dictionary to be a wrapper
        // type instead of alias)
        let mut dictionary = Dictionary::with_capacity(DEFAULT_DICTIONARY_CAPACITY_WORDS);

        populate_primitive_words(&mut dictionary)
            .expect("internal error populating primitive words");

        Self { store, dictionary }
    }
}

type Dictionary = HashMap<String, WordsInDictionary>;

struct WordsInDictionary(Vec<Word>);

impl WordsInDictionary {
    fn new() -> Self {
        Self::new_with_capacity(DEFAULT_DICTIONARY_CAPACITY_PER_WORD)
    }

    fn new_with_capacity(capacity: usize) -> Self {
        Self(Vec::with_capacity(capacity))
    }
}

impl Deref for WordsInDictionary {
    type Target = Vec<Word>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for WordsInDictionary {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl Display for WordsInDictionary {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Words[ ")?;

        for word in &self.0 {
            write!(f, "{}, ", word)?;
        }

        write!(f, "]")?;

        Ok(())
    }
}



fn define_word(dict: &mut Dictionary, identifier: &str, word: Word) -> Result<(), RuntimeError> {
    if !dict.contains_key(identifier) {
        match dict.insert(identifier.to_string(), WordsInDictionary::new()) {
            None => {}
            Some(existing) => unreachable!(
                "Dictionary claims to not contain key {}, but {} was already there",
                identifier, existing
            ),
        }
    }

    dict.get_mut(identifier)
        .map(|impls| {
            impls.push(word);
        })
        .ok_or(RuntimeError::InternalError(
            InternalError::WordInsertionFailed,
        ))
}

fn populate_primitive_words(dict: &mut Dictionary) -> Result<(), RuntimeError> {
    // stack ops
    define_word(
        dict,
        "drop",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_drop),
        },
    )?;

    define_word(
        dict,
        "dup",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_dup),
        },
    )?;

    define_word(
        dict,
        "swap",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_swap),
        },
    )?;

    // math
    define_word(
        dict,
        "add",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_add),
        },
    )?;
    define_word(
        dict,
        "sub",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_sub),
        },
    )?;
    define_word(
        dict,
        "mul",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_mul),
        },
    )?;
    define_word(
        dict,
        "div",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_div),
        },
    )?;
    define_word(
        dict,
        "mod",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_mod),
        },
    )?;

    Ok(())
}

// TODO: handle "peek" syntax (eg. swap/2, which peeks the stack "pointer" backwards by two
// elements before running swap)
fn prim_word_swap(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    store.swap(0, 1);

    Ok(())
}

// TODO: handle "peek" syntax (eg. swap/2, which peeks the stack "pointer" backwards by two
// elements before running swap)
fn prim_word_dup(store: &mut Store) -> WordResult {
    let new_entry = { store.get(0).cloned().ok_or(RuntimeError::StackUnderflow) }?;

    store.insert(0, new_entry);

    Ok(())
}

// TODO: handle "peek" syntax (eg. swap/2, which peeks the stack "pointer" backwards by two
// elements before running swap)
fn prim_word_drop(store: &mut Store) -> WordResult {
    store.pop_front().map(|_| ())
}

fn prim_word_add(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let left = store.pop_front()?;
    let right = store.pop_front()?;
    store.push_front(StoreEntry(left.add(&right)??));

    Ok(())
}

fn prim_word_sub(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let left = store.pop_front()?;
    let right = store.pop_front()?;
    store.push_front(StoreEntry(left.sub(&right)??));

    Ok(())
}

fn prim_word_mul(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let left = store.pop_front()?;
    let right = store.pop_front()?;
    store.push_front(StoreEntry(left.mul(&right)??));

    Ok(())
}

fn prim_word_div(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let left = store.pop_front()?;
    let right = store.pop_front()?;
    store.push_front(StoreEntry(left.div(&right)??));

    Ok(())
}

fn prim_word_mod(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let left = store.pop_front()?;
    let right = store.pop_front()?;
    store.push_front(StoreEntry(left.modu(&right)??));

    Ok(())
}

fn main() -> Result<(), RuntimeError> {
    let stdin = io::stdin();
    let mut runtime = Runtime::default();

    // FIXME: traditionally in a Forth, the REPL is, itself, a Forth program (and thus is hackable
    // at runtime), so this logic will need to be generalized and exposed to the runtime itself,
    // rather than hard-coded here
    loop {
        let mut stdin_buffer = String::new();
        {
            let mut stdin = stdin.lock();
            // NOTE: since we're in vanilla zero-dependency Rust, there's no access to per-byte
            // character streams here: for cross-platform compat reasons, io::Stdin is always
            // line-buffered. TODO allow opting into linenoise (readline), termion,  etc. to enable
            // rich REPL (i.e. syntax highlighting as you type)
            let chars_read = stdin.read_line(&mut stdin_buffer)?;

            // "If this function returns Ok(0), the stream has reached EOF" --
            // https://doc.rust-lang.org/std/io/trait.BufRead.html#method.read_line
            if chars_read == 0 {
                break Ok(());
            }

            if stdin_buffer.trim().is_empty() {
                continue;
            }

            loop {
                match (
                    stdin_buffer.len(),
                    stdin_buffer.split_once(&WORD_SPLITTING_CHARS),
                ) {
                    (0, _) => break,

                    // word is the entirety of the line (no splits found)
                    // TODO: no unwrap, provide error reporting UX in REPL
                    (_, None) => runtime.feed_word(&stdin_buffer).unwrap(),

                    (_, Some((first_word, rest))) => {
                        // TODO: no unwrap, provide error reporting UX in REPL
                        runtime.feed_word(first_word).unwrap();
                        stdin_buffer = rest.into();
                    }
                }

                eprintln!("store is now: {}", runtime.store);
            }
        }

        stdin_buffer.clear();
    }
}

fn attempt_parse_iint_literal(candidate: &str) -> Option<StoreEntry> {
    candidate
        .parse::<isize>()
        .map(|parsed| StoreEntry(Object::Primitive(Primitive::SignedInt(parsed))))
        .ok()
}

fn attempt_parse_uint_literal(candidate: &str) -> Option<StoreEntry> {
    candidate
        .parse::<usize>()
        .map(|parsed| StoreEntry(Object::Primitive(Primitive::UnsignedInt(parsed))))
        .ok()
}

fn attempt_parse_float_literal(candidate: &str) -> Option<StoreEntry> {
    candidate
        .parse::<StandardFloat>()
        .map(|parsed| StoreEntry(Object::Primitive(Primitive::Float(parsed))))
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_store_empty(store: &Store) {
        assert_eq!(store.len(), 0);
    }

    fn push_uint_to_stack(store: &mut Store, val: usize) {
        store.push_front(StoreEntry(Object::Primitive(Primitive::UnsignedInt(val))))
    }

    fn push_int_to_stack(store: &mut Store, val: isize) {
        store.push_front(StoreEntry(Object::Primitive(Primitive::SignedInt(val))))
    }

    fn push_float_to_stack(store: &mut Store, val: StandardFloat) {
        store.push_front(StoreEntry(Object::Primitive(Primitive::Float(val))))
    }

    #[test]
    fn test_swap() -> Result<(), RuntimeError> {
        let mut runtime = Runtime::default();

        assert_store_empty(&runtime.store);

        push_uint_to_stack(&mut runtime.store, 1);
        push_uint_to_stack(&mut runtime.store, 2);
        runtime.feed_word("swap")?;
        assert_eq!(
            runtime.store.pop_front()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );
        assert_eq!(
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );
        assert_eq!(
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
            StoreEntry(Object::Primitive(Primitive::UnsignedInt(1))),
        );

        runtime.feed_word("1")?;
        runtime.feed_word("2")?;
        assert_eq!(
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
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
            runtime.store.pop_front()?,
            StoreEntry(Object::Primitive(Primitive::Float(4.0)),),
        );

        assert_store_empty(&runtime.store);

        Ok(())
    }
}
