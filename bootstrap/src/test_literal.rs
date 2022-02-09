#[cfg(test)]
use crate::{parse_string, Entity, EntityContents, EntityKind, ParsingError, PointInSource};

#[test]
fn number_int() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("1")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 2
            },
            contents: Some(EntityContents::Number("1".into())),
        }],
    );

    Ok(())
}

#[test]
fn number_int_bigger() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("42")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 3
            },
            contents: Some(EntityContents::Number("42".into())),
        }],
    );

    Ok(())
}

/*
#[test]
fn number_int_with_underscores() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("12_345")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 3
            },
            contents: Some(EntityContents::Number("12345".into())),
        }],
    );

    Ok(())
}
*/
