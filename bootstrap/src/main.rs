use argh::FromArgs;

mod lexer;

#[derive(FromArgs)]
/// the primitive-ish bootstrapping compiler for gluumy
pub struct CLIArgs {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Entity {
    pub kind: EntityKind,
    pub start: PointInSource,
    pub end: PointInSource,
    pub contents: Option<EntityContents>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum EntityKind {
    Function,
    ForeignFunction,
    Shape,
    SumShape,
    String,
    CompilerInstruction(CompilerInstruction),
    Comment,
    DocString,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PointInSource {
    pub line_number: usize,
    pub col_number: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum EntityContents {
    Comment(String),
    Docstring(String),
    FFIBody(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CompilerInstruction {
    Primitive(Primitive),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Primitive {
    Boolean,
    Number,
    Shape,
    SumShape,
    String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ParsingError {
    Unspecified,
}

fn main() {
    argh::from_env::<CLIArgs>();
}

pub fn parse_string(input: &str) -> Result<Entity, ParsingError> {
    Err(ParsingError::Unspecified)
}

#[test]
fn test_one_line_comment() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("-- this is a one line comment")?,
        Entity {
            kind: EntityKind::Comment,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 27
            },
            contents: Some(EntityContents::Comment("this is a one line comment".into())),
        },
    );

    Ok(())
}
