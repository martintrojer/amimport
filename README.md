# AMImport

AMImport is a macOS app for importing song lists and matching them to your Apple Music library.

## Import Formats

- CSV is supported first.
- The import parser is plugin-oriented so future formats can be added without changing core matching/export flows.

## CSV Columns

- Required: `title`, `artist`
- Optional: `album`, `duration`, `isrc`

## Matching Strategies

- `exact`: exact title+artist string equality.
- `normalizedExact`: punctuation/case/spacing normalized equality.
- `fuzzy`: edit-distance similarity scoring over normalized title+artist.

## Permissions and Capabilities

- `NSAppleMusicUsageDescription`: allows reading the Apple Music library and writing outputs.
- `NSDocumentsFolderUsageDescription`: allows importing local files (CSV first).

## App Sandbox / Signing Notes

- Enable Apple Music capability for library access.
- Grant file import access via user-selected files.
- Keep import pipeline format-extensible; CSV is the first supported parser.

## Output Modes

- New playlist: creates/uses a playlist in Music and adds resolved tracks.
- Enqueue tracks: sends resolved tracks to Music playback flow.

## Troubleshooting

- If import fails immediately, verify Apple Music permission is granted.
- If rows stay unmatched, lower the minimum score or enable fuzzy matching.
- If export fails, ensure the Music app is installed/running and script permissions are allowed.
