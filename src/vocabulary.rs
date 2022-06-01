use std::collections::HashMap;
use std::rc::Rc;

use crate::internal_error::InternalError;
use crate::runtime_error::RuntimeError;
use crate::word::Word;
use crate::DEFAULT_DICTIONARY_CAPACITY_WORDS;
use crate::MAX_SIMULTANEOUS_VOCABULARIES;

#[derive(Clone)]
pub struct Vocabularies<'rt>(HashMap<&'rt str, Vocabulary>);

impl Vocabularies<'_> {
    pub fn new_with_primitives(prims: Vocabulary) -> Self {
        let mut vocabs = Self::default();
        vocabs.0.insert("__@PRIMITIVES", prims);
        vocabs
    }
}

impl Default for Vocabularies<'_> {
    fn default() -> Self {
        Self(HashMap::with_capacity(MAX_SIMULTANEOUS_VOCABULARIES))
    }
}

pub type WordsByName = HashMap<String, Word>;
#[derive(Clone)]
pub struct Vocabulary {
    dictionary: WordsByName,
    pub name: Rc<String>,
}

impl Vocabulary {
    pub fn new_named(name: &str) -> Self {
        Self {
            dictionary: HashMap::with_capacity(DEFAULT_DICTIONARY_CAPACITY_WORDS).into(),
            name: Rc::new(name.into()),
        }
    }
    pub fn define_word(&mut self, identifier: &str, word: Word) -> Result<(), RuntimeError> {
        if !self.dictionary.contains_key(identifier) {
            match self
                .dictionary
                .insert(identifier.to_string(), WordsInDictionary::new())
            {
                None => {}
                Some(existing) => unreachable!(
                    "Dictionary claims to not contain key {}, but {} was already there",
                    identifier, existing
                ),
            }
        }

        self.dictionary
            .get_mut(identifier)
            .map(|impls| {
                impls.push(word);
            })
            .ok_or(RuntimeError::InternalError(
                InternalError::WordInsertionFailed,
            ))
    }
}
