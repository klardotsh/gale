#[cfg(test)]
use crate::{parse_string, Entity, EntityContents, EntityKind, ParsingError, PointInSource};

#[test]
fn has_one_req_func() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("Printable => repr :: Self -> String")?,
        vec![
            Shape {
                identifier: Some("Printable".into()),
                composition_references: vec![],
                requisite_methods: vec![
                ],
                values: vec![],
            },
            Entity {
                kind: EntityKind::Function,
                start: PointInSource {
                    line_number: 1,
                    col_number: 1
                },
                end: PointInSource {
                    line_number: 2,
                    col_number: 24
                },
                contents: Some(EntityContents::Function("blah".into())),
            },
        ],
    );

    Ok(())
}
