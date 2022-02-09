#[cfg(test)]
use crate::{
    parse_string, Entity, EntityContents, EntityKind, InvalidNumber, ParsingError, PointInSource,
};

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
fn number_int_2() -> Result<(), ParsingError> {
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
                col_number: 7
            },
            contents: Some(EntityContents::Number("12345".into())),
        }],
    );

    Ok(())
}

#[test]
fn number_int_with_underscores_2() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("12_345_678")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 11
            },
            contents: Some(EntityContents::Number("12345678".into())),
        }],
    );

    Ok(())
}

#[test]
fn number_float() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("3.14")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 5
            },
            contents: Some(EntityContents::Number("3.14".into())),
        }],
    );

    Ok(())
}

#[test]
fn number_float_with_underscore() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("1_003.14")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 9
            },
            contents: Some(EntityContents::Number("1003.14".into())),
        }],
    );

    Ok(())
}

#[test]
fn number_float_with_underscore_2() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("1_003.141_5")?,
        vec![Entity {
            kind: EntityKind::Number,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 12
            },
            contents: Some(EntityContents::Number("1003.1415".into())),
        }],
    );

    Ok(())
}

#[test]
fn number_with_multiple_decimal_err() {
    assert_eq!(
        parse_string("3.14.15"),
        Err(ParsingError::InvalidNumber(
            InvalidNumber::TooManyDecimalPoints,
            1,
            5
        )),
    )
}
