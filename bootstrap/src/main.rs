use argh::FromArgs;
use unicode_segmentation::UnicodeSegmentation;

mod lexer;
mod test_comment;
mod test_hashbang;
mod test_literal;

#[derive(FromArgs)]
/// the primitive-ish bootstrapping compiler for gluumy
struct CLIArgs {}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Entity {
    kind: EntityKind,
    start: PointInSource,
    end: PointInSource,
    contents: Option<EntityContents>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum EntityKind {
    Function,
    ForeignFunction,
    Shape,
    SumShape,
    String,
    Number,
    Boolean,
    CompilerInstruction(CompilerInstruction),
    HashBang,
    Comment,
    DocString,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct PointInSource {
    line_number: usize,
    col_number: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum EntityContents {
    CompilerHint(String),
    HashBang(String),
    Comment(String),
    Docstring(String),
    FFIBody(String),
    Number(String),
}

impl EntityContents {
    fn append(&mut self, content: &str) {
        match self {
            EntityContents::CompilerHint(inner)
            | EntityContents::HashBang(inner)
            | EntityContents::Comment(inner)
            | EntityContents::Docstring(inner)
            | EntityContents::FFIBody(inner)
            | EntityContents::Number(inner) => {
                inner.push_str(content);
            }
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum CompilerInstruction {
    Primitive(Primitive),
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Primitive {
    Boolean,
    Number,
    Shape,
    SumShape,
    String,
}

#[derive(Clone, Debug)]
struct EntityBuilder {
    kind: Option<EntityKind>,
    start: Option<PointInSource>,
    end: Option<PointInSource>,
    contents: Option<EntityContents>,
}

impl EntityBuilder {
    fn new() -> Self {
        Self {
            kind: None,
            start: None,
            end: None,
            contents: None,
        }
    }

    fn finalize_and_build(&mut self) -> Result<Entity, EntityBuildError> {
        self.finalize();
        self.build()
    }

    fn build(&self) -> Result<Entity, EntityBuildError> {
        Ok(Entity {
            kind: self.kind.clone().ok_or(EntityBuildError::MissingKind)?,
            start: self.start.clone().ok_or(EntityBuildError::MissingStart)?,
            end: self.end.clone().ok_or(EntityBuildError::MissingEnd)?,
            contents: self.contents.clone(),
        })
    }

    fn finalize(&mut self) -> &Self {
        self.trim_content_if_applicable();
        self
    }

    fn kind(&mut self, kind: EntityKind) -> &Self {
        self.kind = Some(kind);
        self
    }

    fn start(&mut self, start: PointInSource) -> &Self {
        self.start = Some(start);
        self
    }

    fn end(&mut self, end: PointInSource) -> &Self {
        self.end = Some(end);
        self
    }

    fn contents(&mut self, contents: EntityContents) -> &Self {
        self.contents = Some(contents);
        self
    }

    fn append_content(&mut self, content: &str) -> Result<&Self, EntityBuildError> {
        match self.contents.as_mut() {
            None => Err(EntityBuildError::ContentsNotInitialized),
            Some(contents) => {
                contents.append(content);
                Ok(self)
            }
        }
    }

    fn trim_content_if_applicable(&mut self) -> &Self {
        match self.contents.as_mut() {
            None => {}
            Some(EntityContents::CompilerHint(content)) => {
                self.contents = Some(EntityContents::CompilerHint(content.trim().into()))
            }
            Some(EntityContents::HashBang(content)) => {
                self.contents = Some(EntityContents::HashBang(content.trim().into()))
            }
            Some(EntityContents::Comment(content)) => {
                self.contents = Some(EntityContents::Comment(content.trim().into()))
            }
            Some(EntityContents::Docstring(content)) => {
                self.contents = Some(EntityContents::Docstring(content.trim().into()))
            }
            Some(EntityContents::Number(content)) => {
                self.contents = Some(EntityContents::Number(content.trim().into()))
            }
            Some(EntityContents::FFIBody(..)) => unimplemented!(),
        };

        self
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum EntityBuildError {
    MissingKind,
    MissingStart,
    MissingEnd,
    ContentsNotInitialized,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum ParsingError {
    Unspecified,
    InternalError {
        subsection: CompilerSubsection,
        message: String,
    },
    HashBangFoundOutsideFirstLine(usize, usize),
}

impl From<&EntityBuildError> for ParsingError {
    fn from(ebe: &EntityBuildError) -> Self {
        Self::InternalError {
            subsection: CompilerSubsection::EntityBuilder,
            message: match ebe {
                EntityBuildError::MissingKind => "entity in progress lacks a kind".into(),
                EntityBuildError::MissingStart => "entity in progress lacks a start".into(),
                EntityBuildError::MissingEnd => "entity in progress lacks an end".into(),
                EntityBuildError::ContentsNotInitialized => {
                    "entity contents are not initialized".into()
                }
            },
        }
    }
}

impl From<EntityBuildError> for ParsingError {
    fn from(ebe: EntityBuildError) -> Self {
        (&ebe).into()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum CompilerSubsection {
    EntityBuilder,
}

fn main() {
    argh::from_env::<CLIArgs>();
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum ParserState {
    FloatingInTheAbyss,
    CompilerHint,
    HashBang,
    Comment,
    Docstring,
    Number,
    BareIdentifier,
    BareIdentifierThatMayBecomeFunctionCall,
    FunctionDefinition,
    FunctionCall,
    ShapeDefinition(ShapeDefinitionSubState),
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum ShapeDefinitionSubState {
    BareIdentifier,
    Include,
    FunctionDefinition,
    Comment,
    Docstring,
}

fn parse_string(input: &str) -> Result<Vec<Entity>, ParsingError> {
    let mut entities: Vec<Entity> = Vec::new();
    let mut state: ParserState = ParserState::FloatingInTheAbyss;
    let mut last: Option<&str> = None;
    let mut lastlast: Option<&str> = None;
    let mut entity: Option<EntityBuilder> = None;
    let mut entity_indent_level: u16 = 0;
    let mut line_number: usize = 1;
    let mut col_number: usize = 1;
    let mut indent_level: u16 = 0;

    for grapheme in UnicodeSegmentation::graphemes(input, true) {
        // this loop allows characters to be matched in multiple blocks if needed. the example case
        // that introduced this was !, which is a valid character in a comment (or a string, or so
        // many places), but has special meaning in HashBang lines that we need to capture
        let mut grapheme_tries: usize = 0;
        loop {
            match (grapheme, grapheme_tries) {
                ("#", 0) => match state {
                    ParserState::FloatingInTheAbyss => {
                        state = ParserState::CompilerHint;
                        break;
                    }
                    _ => {}
                },

                ("!", 0) => match (&state, last, line_number, col_number) {
                    (ParserState::CompilerHint, Some("#"), 1, 2) => {
                        state = ParserState::HashBang;
                        let mut entity_builder = EntityBuilder::new();
                        entity_builder.kind(EntityKind::HashBang);
                        entity_builder.start(PointInSource {
                            line_number,
                            col_number: col_number - 1,
                        });
                        entity_builder.contents(EntityContents::HashBang(String::new()));
                        entity = Some(entity_builder);
                        break;
                    }
                    (ParserState::CompilerHint, Some("#"), other_line, other_col) => {
                        return Err(ParsingError::HashBangFoundOutsideFirstLine(
                            other_line, other_col,
                        ))
                    }
                    (ParserState::Comment | ParserState::Docstring, _, _, _) => {}
                    _ => unimplemented!(),
                },

                ("-", 0) => {
                    if lastlast == Some("-") && last == Some("-") {
                        state = if state == ParserState::Docstring {
                            ParserState::FloatingInTheAbyss
                        } else {
                            ParserState::Docstring
                        };
                    } else if last == Some("-") {
                        state = ParserState::Comment;
                        let mut entity_builder = EntityBuilder::new();
                        entity_builder.kind(EntityKind::Comment);
                        entity_builder.start(PointInSource {
                            line_number,
                            col_number: col_number - 1,
                        });
                        entity_builder.contents(EntityContents::Comment(String::new()));
                        entity = Some(entity_builder);
                    }

                    break;
                }

                ("1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "0", 0) => match state {
                    ParserState::FloatingInTheAbyss => {
                        state = ParserState::Number;
                        let mut entity_builder = EntityBuilder::new();
                        entity_builder.kind(EntityKind::Number);
                        entity_builder.start(PointInSource {
                            line_number,
                            col_number,
                        });
                        entity_builder.contents(EntityContents::Number(String::with_capacity(5)));
                        entity_builder.append_content(grapheme)?;
                        entity = Some(entity_builder);
                        break;
                    }
                    _ => {}
                },

                ("\n" | "\r\n", 0) => {
                    match state {
                        ParserState::FloatingInTheAbyss
                        | ParserState::Docstring
                        | ParserState::BareIdentifierThatMayBecomeFunctionCall => {}

                        ParserState::BareIdentifier => {
                            state = ParserState::BareIdentifierThatMayBecomeFunctionCall;
                            entity_indent_level = indent_level;
                        }

                        ParserState::Comment | ParserState::HashBang | ParserState::Number => {
                            // TODO: comments across multiple lines should be merged, but the line
                            // after a comment starts a new entity
                            match entity.as_mut() {
                                Some(prepared) => {
                                    prepared.end(PointInSource {
                                        line_number,
                                        col_number: col_number - 1,
                                    });
                                    let built = prepared.finalize_and_build()?;
                                    entities.push(built);
                                    entity = None;
                                }
                                _ => unreachable!(),
                            }
                        }

                        ParserState::CompilerHint
                        | ParserState::FunctionCall
                        | ParserState::FunctionDefinition
                        | ParserState::ShapeDefinition(..) => unimplemented!(),
                    }

                    line_number += 1;
                    col_number = 0; // since we'll increase this again in this loop iter, use 0
                    break;
                }

                (other, _) => {
                    match state {
                        ParserState::Comment
                        | ParserState::Docstring
                        | ParserState::HashBang
                        | ParserState::Number => match entity.as_mut() {
                            Some(entity) => {
                                entity.append_content(other)?;
                            }
                            None => unreachable!(),
                        },
                        _ => unimplemented!(),
                    }
                    break;
                }
            }

            grapheme_tries += 1;
        }

        lastlast = last;
        last = Some(grapheme);
        col_number += 1;
    }

    match entity.as_mut() {
        Some(prepared) => {
            prepared.end(PointInSource {
                line_number,
                col_number,
            });
            let built = prepared.finalize_and_build()?;
            entities.push(built);
        }
        // if the stream ends on an content-free line, just move on
        None => {}
    };

    Ok(entities)
}
