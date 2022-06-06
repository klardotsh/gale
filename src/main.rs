// gluumy: a hackable, type-safe, minimalist, stack-based programming language
//
// (it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase, always)
//
//  _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
// (_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
//        _|                 /           _|                   _|

mod internal_error;
mod object;
mod runtime;
mod runtime_error;
mod store;
mod vocabulary;
mod word;

use object::Object;
use runtime::Runtime;
use runtime_error::RuntimeError;
use word::Word;

use std::collections::HashMap;
use std::fmt::{self, Display};
use std::io::{self, BufRead};
use std::ops::{Deref, DerefMut};

// 31 "user" vocabularies, plus a primitives vocabulary specific to this implementation of gluumy.
// It's not strictly required that a gluumy implementation be built in the Forth style of
// bootstrapping from nearly nothing; until you get to the words defined in the spec (TODO:
// document what words are actually part of the spec, and explicitly call out which are specific to
// this implementation - want to avoid the CPython problem if I can...) there's no restrictions on
// moving the _entire_ language implementation into the host language if one so desired. Of
// particular note, that'll be necessary for a gluumy that targets constrained environments like
// Uxn, which simply doesn't have the RAM to be storing more HashMaps than strictly necessary.
const DEFAULT_VOCABULARIES_CAPACITY: usize = 32;

const DEFAULT_DICTIONARY_CAPACITY_WORDS: usize = 1024;
const DEFAULT_DICTIONARY_CAPACITY_PER_WORD: usize = 3;

const WORD_SPLITTING_CHARS: [char; 3] = [' ', '\t', '\n'];

type StandardFloat = f64;

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

fn attempt_parse_iint_literal(candidate: &str) -> Option<Object> {
    candidate
        .parse::<isize>()
        .map(|parsed| Object::SignedInt(parsed))
        .ok()
}

fn attempt_parse_uint_literal(candidate: &str) -> Option<Object> {
    candidate
        .parse::<usize>()
        .map(|parsed| Object::UnsignedInt(parsed))
        .ok()
}

fn attempt_parse_f64_literal(candidate: &str) -> Option<Object> {
    candidate
        .parse::<StandardFloat>()
        .map(|parsed| Object::Float64(parsed))
        .ok()
}
