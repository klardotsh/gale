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
            "-- this is a one line comment, but with Japanese characters: すてきな一日を"
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
                "this is a one line comment, but with Japanese characters: すてきな一日を".into()
            )),
        }],
    );

    Ok(())
}

#[test]
fn one_line_weird_stuff() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("--hello \n-- 1 new # line, woo hoo!\n")?,
        vec![
            Entity {
                kind: EntityKind::Comment,
                start: PointInSource {
                    line_number: 1,
                    col_number: 1
                },
                end: PointInSource {
                    line_number: 1,
                    col_number: 8
                },
                contents: Some(EntityContents::Comment("hello".into())),
            },
            Entity {
                kind: EntityKind::Comment,
                start: PointInSource {
                    line_number: 2,
                    col_number: 1
                },
                end: PointInSource {
                    line_number: 2,
                    col_number: 25
                },
                contents: Some(EntityContents::Comment("1 new # line, woo hoo!".into())),
            }
        ],
    );

    Ok(())
}
