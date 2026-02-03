# AMImport

AMImport is a macOS app for importing song lists and matching them to your Apple Music library.

## Permissions and Capabilities

- `NSAppleMusicUsageDescription`: allows reading the Apple Music library and writing outputs.
- `NSDocumentsFolderUsageDescription`: allows importing local files (CSV first).

## App Sandbox / Signing Notes

- Enable Apple Music capability for library access.
- Grant file import access via user-selected files.
- Keep import pipeline format-extensible; CSV is the first supported parser.
