// gluumy: a hackable, type-safe, minimalist, stack-based programming language
//
// (it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase, always)
//
//  _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
// (_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
//        _|                 /           _|                   _|
//
//
// Hi, welcome to the party, my name is klardotsh and I'll be your tour guide this evening. Before
// we begin, let's take a quick moment to make sure your editor is in a sane state for reading
// this:
//
// 1) it needs to be wide enough to see the trailing > at the end of the next line:
// <----------------------------------------------------------------------------------------------->
//
// look yes I know that's 100 characters but *it's 2022 for zeus's sake*
//
// 2) it needs to be able to handle UTF-8! again, *it's 20-freakin-22*, we
//    standardized this stuff years ago
//
//
// Cool, now let's also make sure your host system, assuming you actually want to build this thing
// (and I hope you do, and I hope you play with it and build awesome things with it!), is in order.
// At time of writing, gluumy builds against Rust 1.59 or newer, supporting the Rust 2021
// specification. Assume this code is not, and will never be, backwards-compatible to Rust 1.58 or
// any previous versions; if it is, consider it a happy little accident. Aside from the Rust
// standard library, the basic gluumy REPL has no system-level dependencies, and almost no Cargo
// dependencies. (I'm aware however that, at time of writing, Rust itself requires a full
// Clang+LLVM stack, and thus bootstrapping gluumy on non-standard architectures may be painful).
//
//
// With that said, let's begin the "host" side of gluumy.

use std::collections::HashMap;
use std::collections::VecDeque;
use std::fmt::{self, Display};
use std::io::{self, BufRead};
use std::ops::{Deref, DerefMut};

// First, let's set up some constants. WORD_BUF_LEN is how big of a buffer we're willing to
// allocate to store words as they're input (be that by keyboard or by source file: we'll see how
// that works later). We have to draw a line _somewhere_, and since 1KB of RAM is beyond feasible
// to allocate on most systems I'd foresee writing gluumy for, that's the max word length until I'm
// convinced otherwise. This should be safe to change and the implementation will scale
// proportionally.
const WORD_BUF_LEN: usize = 1024;

const MAX_STORE_SIZE: usize = 4096; // arbitrary for now

const DEFAULT_DICTIONARY_CAPACITY_WORDS: usize = 1024;
const DEFAULT_DICTIONARY_CAPACITY_PER_WORD: usize = 3;

const WORD_SPLITTING_CHARS: [char; 3] = [' ', '\t', '\n'];

type StandardFloat = f64;

type StoreContainer = VecDeque<StoreEntry>;
struct Store {
    container: StoreContainer,
}

impl Store {
    fn with_capacity(capacity: usize) -> Self {
        Store {
            container: StoreContainer::with_capacity(capacity),
        }
    }

    fn len(&self) -> usize {
        self.container.len()
    }

    fn push_front(&mut self, item: StoreEntry) {
        self.container.push_front(item)
    }

    fn pop_front(&mut self) -> Result<StoreEntry, RuntimeError> {
        self.container
            .pop_front()
            .ok_or(RuntimeError::StackUnderflow)
    }

    fn get(&self, i: usize) -> Option<&StoreEntry> {
        self.container.get(i)
    }

    fn swap(&mut self, i: usize, j: usize) {
        self.container.swap(i, j)
    }

    fn insert(&mut self, i: usize, obj: StoreEntry) {
        self.container.insert(i, obj)
    }
}

impl Display for Store {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Store[ ")?;

        for entry in &self.container {
            write!(f, "{}, ", entry)?;
        }

        write!(f, "]")?;

        Ok(())
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

#[derive(Clone, Debug, PartialEq)]
struct StoreEntry {
    type_signature: TypeSignature,
    value: Object,
}

impl Display for StoreEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Item<{}>({})", self.type_signature, self.value)?;

        Ok(())
    }
}

impl Deref for StoreEntry {
    type Target = Object;

    fn deref(&self) -> &Self::Target {
        &self.value
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Object {
    Primitive(Primitive),
    // TODO: complex things (dictionaries, lists, whatever) and foreign things (C ABI)
}

impl Object {
    fn mul(&self, other: &Self) -> Result<Result<Self, RuntimeError>, ObjectMethodError> {
        match (self, other) {
            (Self::Primitive(prim_self), Self::Primitive(prim_other)) => {
                Ok(prim_self.mul(prim_other).map(Self::Primitive))
            }
        }
    }
}

impl Display for Object {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Primitive(prim) => write!(f, "{}", prim),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
enum ObjectMethodError {
    MethodDoesNotApplyToObjectKind,
}

#[derive(Clone, Debug, PartialEq)]
struct TypeSignature {}

impl Display for TypeSignature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "?")
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Primitive {
    Boolean(bool),
    UnsignedInt(usize),
    SignedInt(isize),
    Float(StandardFloat),
}

impl Primitive {
    fn mul(&self, other: &Self) -> Result<Self, RuntimeError> {
        // TODO: should implicit `into` be allowed here?
        match (self, other) {
            (Self::UnsignedInt(left), Self::UnsignedInt(right)) => {
                Ok(Self::UnsignedInt(left * right))
            }
            (Self::SignedInt(left), Self::SignedInt(right)) => Ok(Self::SignedInt(left * right)),
            (Self::Float(left), Self::Float(right)) => Ok(Self::Float(left * right)),

            (Self::UnsignedInt(_), Self::SignedInt(_))
            | (Self::SignedInt(_), Self::UnsignedInt(_))
            | (Self::UnsignedInt(_), Self::Float(_))
            | (Self::Float(_), Self::UnsignedInt(_))
            | (Self::SignedInt(_), Self::Float(_))
            | (Self::Float(_), Self::SignedInt(_)) => unimplemented!(),

            (Self::Boolean(_), _) | (_, Self::Boolean(_)) => Err(RuntimeError::IncompatibleTypes),
        }
    }
}

impl Display for Primitive {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Boolean(prim) => write!(f, "{}", prim),
            Self::SignedInt(prim) => write!(f, "{}", prim),
            Self::UnsignedInt(prim) => write!(f, "{}", prim),
            Self::Float(prim) => write!(f, "{}", prim),
        }
    }
}

struct Word {
    immediate: bool,
    hidden: bool,
    implementation: WordImplementation,
}

impl Display for Word {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match (self.immediate, self.hidden) {
            (false, false) => write!(f, "word with implementation: {}", self.implementation),
            (false, true) => write!(
                f,
                "word (hidden) with implementation: {}",
                self.implementation
            ),
            (true, false) => write!(
                f,
                "immediate word with implementation: {}",
                self.implementation
            ),
            (true, true) => write!(
                f,
                "immediate word (hidden) with implementation: {}",
                self.implementation
            ),
        }
    }
}

enum WordImplementation {
    Primitive(PrimitiveImplementation),
    WordSequence(Vec<Word>),
    Constant(Object),
}

impl Display for WordImplementation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WordImplementation::Primitive(_) => write!(f, "<native method>"),
            _ => unimplemented!(),
        }
    }
}

type WordResult = Result<(), RuntimeError>;
type PrimitiveImplementation = fn(&mut Store) -> WordResult;

#[derive(Clone, Debug, PartialEq)]
enum RuntimeError {
    InternalError(InternalError),
    StackUnderflow,
    StackOverflow,
    IncompatibleTypes,
    NoWordsByName(String),
}

impl From<io::Error> for RuntimeError {
    fn from(src: io::Error) -> Self {
        Self::InternalError(src.into())
    }
}

impl From<ObjectMethodError> for RuntimeError {
    fn from(src: ObjectMethodError) -> Self {
        Self::InternalError(src.into())
    }
}

#[derive(Clone, Debug, PartialEq)]
enum InternalError {
    // TODO: see if there's a better way to store this than just stringifying it; io::Error does
    // not implement PartialEq due to a Custom error kind in the return set
    IOError(String),

    ObjectMethodError(ObjectMethodError),
    WordInsertionFailed,
}

impl From<io::Error> for InternalError {
    fn from(src: io::Error) -> Self {
        Self::IOError(src.to_string())
    }
}

impl From<ObjectMethodError> for InternalError {
    fn from(src: ObjectMethodError) -> Self {
        Self::ObjectMethodError(src)
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
        "*",
        Word {
            hidden: false,
            immediate: false,
            implementation: WordImplementation::Primitive(prim_word_mul),
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

fn prim_word_mul(store: &mut Store) -> WordResult {
    if store.len() < 2 {
        return Err(RuntimeError::StackUnderflow);
    }

    let left = store.pop_front()?;
    let right = store.pop_front()?;
    store.push_front(StoreEntry {
        type_signature: TypeSignature {},
        value: left.mul(&right)??,
    });

    Ok(())
}

fn main() -> Result<(), RuntimeError> {
    let stdin = io::stdin();
    let (mut store, dictionary) = construct_default_runtime()?;

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
                    (_, None) => runtime_feed_word(&mut store, &dictionary, &stdin_buffer).unwrap(),

                    (_, Some((first_word, _))) => {
                        // TODO: no unwrap, provide error reporting UX in REPL
                        runtime_feed_word(&mut store, &dictionary, first_word).unwrap();

                        // TODO fix this compiler warning; indeed this combo of borrowing feels like a
                        // code smell, but I'm too lazy to bother fixing it right now
                        stdin_buffer = stdin_buffer.split_off(first_word.len() + 1);
                    }
                }

                eprintln!("store is now: {}", store);
            }
        }

        stdin_buffer.clear();
    }
}

fn runtime_feed_word(
    store: &mut Store,
    dictionary: &Dictionary,
    word_str: &str,
) -> Result<(), RuntimeError> {
    dictionary
        .get(word_str)
        .ok_or_else(|| RuntimeError::NoWordsByName(word_str.into()))
        .and_then(|impls| {
            // NOTE: for now we're lazy and just use the last (newest) definition of a word that
            // isn't hidden. FIXME integrate type system when it exists, and consider the
            // (potential?) need for, like in jonesForth and most other ASM Forths, retaining
            // references to old versions of words (eg A is defined, B is defined with a ref to A,
            // and then A is redefined/overwritten)
            impls
                .iter()
                .position(|candidate| !candidate.hidden)
                .and_then(|word_idx| impls.get(word_idx))
                .and_then(|word| match word.implementation {
                    WordImplementation::Primitive(prim_impl) => Some(prim_impl(store)),
                    _ => unimplemented!(),
                })
                .ok_or_else(|| RuntimeError::NoWordsByName(word_str.into()))
        })
        .or_else(|err| match err {
            // word not found in dictionary, so before throwing an error, let's try to parse it as
            // a primitive. since this is _always_ the fallback case, this implies that defining a
            // word `1` can and will overwrite the primitive number 1. with great power comes great
            // responsibility, friends.
            #[allow(clippy::unnecessary_lazy_evaluations)]
            RuntimeError::NoWordsByName(_) => attempt_parse_uint_literal(word_str)
                .or_else(|| attempt_parse_iint_literal(word_str))
                .or_else(|| attempt_parse_float_literal(word_str))
                .ok_or_else(|| err)
                .map(|entry| {
                    store.push_front(entry);
                    Ok(())
                }),

            _ => Err(err),
        })
        .map(|_| ())
}

fn attempt_parse_iint_literal(candidate: &str) -> Option<StoreEntry> {
    candidate
        .parse::<isize>()
        .map(|parsed| StoreEntry {
            type_signature: TypeSignature {},
            value: Object::Primitive(Primitive::SignedInt(parsed)),
        })
        .ok()
}

fn attempt_parse_uint_literal(candidate: &str) -> Option<StoreEntry> {
    candidate
        .parse::<usize>()
        .map(|parsed| StoreEntry {
            type_signature: TypeSignature {},
            value: Object::Primitive(Primitive::UnsignedInt(parsed)),
        })
        .ok()
}

fn attempt_parse_float_literal(candidate: &str) -> Option<StoreEntry> {
    candidate
        .parse::<StandardFloat>()
        .map(|parsed| StoreEntry {
            type_signature: TypeSignature {},
            value: Object::Primitive(Primitive::Float(parsed)),
        })
        .ok()
}

fn construct_default_runtime() -> Result<(Store, Dictionary), RuntimeError> {
    let store = construct_default_store();
    let mut dictionary = Dictionary::with_capacity(DEFAULT_DICTIONARY_CAPACITY_WORDS);

    populate_primitive_words(&mut dictionary)?;

    Ok((store, dictionary))
}

fn construct_default_store() -> Store {
    Store::with_capacity(MAX_STORE_SIZE)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_store_empty(store: &Store) {
        assert_eq!(store.len(), 0);
    }

    fn push_uint_to_stack(store: &mut Store, val: usize) {
        store.push_front(StoreEntry {
            type_signature: TypeSignature {},
            value: Object::Primitive(Primitive::UnsignedInt(val)),
        })
    }

    fn push_int_to_stack(store: &mut Store, val: isize) {
        store.push_front(StoreEntry {
            type_signature: TypeSignature {},
            value: Object::Primitive(Primitive::SignedInt(val)),
        })
    }

    fn push_float_to_stack(store: &mut Store, val: StandardFloat) {
        store.push_front(StoreEntry {
            type_signature: TypeSignature {},
            value: Object::Primitive(Primitive::Float(val)),
        })
    }

    #[test]
    fn test_mul_underflow() -> Result<(), RuntimeError> {
        let mut store = construct_default_store();
        assert_eq!(prim_word_mul(&mut store), Err(RuntimeError::StackUnderflow),);
        push_uint_to_stack(&mut store, 1);
        assert_eq!(prim_word_mul(&mut store), Err(RuntimeError::StackUnderflow),);
        Ok(())
    }

    #[test]
    fn test_mul_uints() -> Result<(), RuntimeError> {
        let mut store = construct_default_store();

        push_uint_to_stack(&mut store, 2);
        push_uint_to_stack(&mut store, 2);
        prim_word_mul(&mut store)?;

        assert_eq!(
            store.pop_front()?,
            StoreEntry {
                type_signature: TypeSignature {},
                value: Object::Primitive(Primitive::UnsignedInt(4)),
            },
        );

        assert_store_empty(&store);

        Ok(())
    }

    #[test]
    fn test_mul_iints() -> Result<(), RuntimeError> {
        let mut store = construct_default_store();

        push_int_to_stack(&mut store, 2);
        push_int_to_stack(&mut store, 2);
        prim_word_mul(&mut store)?;

        assert_eq!(
            store.pop_front()?,
            StoreEntry {
                type_signature: TypeSignature {},
                value: Object::Primitive(Primitive::SignedInt(4)),
            },
        );

        assert_store_empty(&store);

        Ok(())
    }

    #[test]
    // NOTE: this test may be blippy if float math does what float math likes to do and returns,
    // say, 3.9999999999999999. may be worth building a bunch of deconstructor methods to access
    // the inner float of a Primitive, rounding it to the nearest int, and comparing to usize(4)
    // here instead
    fn test_mul_floats() -> Result<(), RuntimeError> {
        let mut store = construct_default_store();

        push_float_to_stack(&mut store, 2.0);
        push_float_to_stack(&mut store, 2.0);
        prim_word_mul(&mut store)?;

        assert_eq!(
            store.pop_front()?,
            StoreEntry {
                type_signature: TypeSignature {},
                value: Object::Primitive(Primitive::Float(4.0)),
            },
        );

        assert_store_empty(&store);

        Ok(())
    }

    #[test]
    fn test_uint_literal() -> Result<(), RuntimeError> {
        let (mut store, dictionary) = construct_default_runtime()?;

        assert_store_empty(&store);

        runtime_feed_word(&mut store, &dictionary, "1")?;
        assert_eq!(
            store.pop_front()?.value,
            Object::Primitive(Primitive::UnsignedInt(1)),
        );

        runtime_feed_word(&mut store, &dictionary, "1")?;
        runtime_feed_word(&mut store, &dictionary, "2")?;
        assert_eq!(
            store.pop_front()?.value,
            Object::Primitive(Primitive::UnsignedInt(2)),
        );

        Ok(())
    }

    #[test]
    fn test_swap() -> Result<(), RuntimeError> {
        let (mut store, dictionary) = construct_default_runtime()?;

        assert_store_empty(&store);

        push_uint_to_stack(&mut store, 1);
        push_uint_to_stack(&mut store, 2);
        runtime_feed_word(&mut store, &dictionary, "swap")?;
        assert_eq!(
            store.pop_front()?.value,
            Object::Primitive(Primitive::UnsignedInt(1)),
        );
        assert_eq!(
            store.pop_front()?.value,
            Object::Primitive(Primitive::UnsignedInt(2)),
        );

        Ok(())
    }

    #[test]
    fn test_dup() -> Result<(), RuntimeError> {
        let (mut store, dictionary) = construct_default_runtime()?;

        assert_store_empty(&store);

        push_uint_to_stack(&mut store, 1);
        runtime_feed_word(&mut store, &dictionary, "dup")?;
        assert_eq!(
            store.pop_front()?.value,
            Object::Primitive(Primitive::UnsignedInt(1)),
        );
        assert_eq!(
            store.pop_front()?.value,
            Object::Primitive(Primitive::UnsignedInt(1)),
        );

        Ok(())
    }
}
