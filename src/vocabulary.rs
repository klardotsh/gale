use std::collections::HashMap;
use std::rc::Rc;

use crate::internal_error::InternalError;
use crate::runtime_error::RuntimeError;
use crate::word::Word;
use crate::DEFAULT_DICTIONARY_CAPACITY_WORDS;
use crate::DEFAULT_VOCABULARIES_CAPACITY;

#[derive(Clone)]
pub struct Vocabularies(pub HashMap<Rc<String>, Vocabulary>);

impl Default for Vocabularies {
    fn default() -> Self {
        Self(HashMap::with_capacity(DEFAULT_VOCABULARIES_CAPACITY))
    }
}

pub type WordsByName = HashMap<String, Word>;
#[derive(Clone, Debug, PartialEq)]
pub struct Vocabulary {
    dictionary: WordsByName,
    when_word_missing: Option<Word>,
    pub name: Rc<String>,
}

impl Vocabulary {
    pub fn new_named(name: &str) -> Self {
        Self {
            dictionary: HashMap::with_capacity(DEFAULT_DICTIONARY_CAPACITY_WORDS).into(),
            name: Rc::new(name.into()),
            when_word_missing: None,
        }
    }

    pub fn define_word(&mut self, identifier: &str, word: Word) -> Result<(), RuntimeError> {
        if !self.dictionary.contains_key(identifier) {
            match self.dictionary.insert(identifier.to_string(), word) {
                None => {}
                Some(existing) => unreachable!(
                    "Dictionary claims to not contain key {}, but {} was already there",
                    identifier, existing
                ),
            }
        }

        // TODO: implement type-based polymorphism
        self.dictionary
            .get(identifier)
            .map(|_| ())
            .ok_or(RuntimeError::InternalError(
                InternalError::WordInsertionFailed,
            ))
    }
}
