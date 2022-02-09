#[cfg(test)]
use crate::{parse_string, Entity, EntityContents, EntityKind, ParsingError, PointInSource};

#[test]
fn simple() -> Result<(), ParsingError> {
    assert_eq!(
        parse_string("#!/usr/bin/env gluumyc")?,
        vec![Entity {
            kind: EntityKind::HashBang,
            start: PointInSource {
                line_number: 1,
                col_number: 1
            },
            end: PointInSource {
                line_number: 1,
                col_number: 23
            },
            contents: Some(EntityContents::HashBang("/usr/bin/env gluumyc".into())),
        }],
    );

    Ok(())
}
