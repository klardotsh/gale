#[cfg(test)]
use crate::{parse_string, Entity, EntityContents, EntityKind, ParsingError, PointInSource};

#[test]
fn one_line() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("-- this is a one line comment")?,
        vec![Entity {
            kind: EntityKind::Comment,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 30
            },
            contents: Some(EntityContents::Comment("this is a one line comment".into())),
        },],
    );

    Ok(())
}

#[test]
fn one_line_unicode() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string(
            "-- this is a one-line comment, but with Japanese characters: すてきな一日を"
        )?,
        vec![Entity {
            kind: EntityKind::Comment,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 69
            },
            contents: Some(EntityContents::Comment(
                "this is a one-line comment, but with Japanese characters: すてきな一日を".into()
            )),
        }],
    );

    Ok(())
}

#[test]
fn one_line_weird_stuff() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("--hello. \n-- 1 new #_ line, woo hoo!\n")?,
        vec![
            Entity {
                kind: EntityKind::Comment,
                start: PointInSource {
                    line_number: 1,
                    col_number: 1
                },
                end: PointInSource {
                    line_number: 1,
                    col_number: 9
                },
                contents: Some(EntityContents::Comment("hello.".into())),
            },
            Entity {
                kind: EntityKind::Comment,
                start: PointInSource {
                    line_number: 2,
                    col_number: 1
                },
                end: PointInSource {
                    line_number: 2,
                    col_number: 26
                },
                contents: Some(EntityContents::Comment("1 new #_ line, woo hoo!".into())),
            }
        ],
    );

    Ok(())
}

#[test]
fn docstring() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("---\nblah\n---")?,
        vec![Entity {
            kind: EntityKind::DocString,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 3,
                col_number: 4
            },
            contents: Some(EntityContents::Docstring("blah".into())),
        },],
    );

    Ok(())
}
