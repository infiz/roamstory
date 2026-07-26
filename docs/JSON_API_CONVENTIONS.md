# JSON API conventions

RoamStory-owned JSON fields use lower camel case. Identifier suffixes are always
spelled `Uuid`, such as `tripUuid`, `mediaUuid`, and `revisionUuid`.

Every Swift API request and response model must define every wire field in
`CodingKeys`. Do not rely on synthesized property-name mapping.

The Rust server defines the same names with an explicit `#[serde(rename =
"...")]` on every field. New or changed contracts require tests, particularly
for names containing initialisms such as `Uuid` and `Url`.
