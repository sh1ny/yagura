# Round-trip corpus

Byte-exact fixtures for the lossless parsers. `.gitattributes` in this
directory disables all text normalisation, so line endings, BOMs and trailing
whitespace reach the tests exactly as stored here. Never reformat these files.

Downloaded files are kept byte for byte as fetched (2026-10-20). Derived files
are produced mechanically from a downloaded file, as noted. Files marked
"hand-written" were not downloaded.

## Downloaded (real files)

| File | Source |
|---|---|
| `cfggameplay.json` | `dayzOffline.chernarusplus/cfggameplay.json` from <https://github.com/BohemiaInteractive/DayZ-Central-Economy>, branch `master` at commit `f220b2918b1d79a5055b1ee9be70c0ec1516e876`. Bohemia Interactive's official central-economy repository. LF endings, tab/space mixed indentation, no final newline. |
| `serverDZ.cfg` | `dayz/config/serverDZ.cfg` from <https://github.com/pelican-eggs/games-steamcmd> at commit `68aa3847dda477c9e5cb0522295b212042f746af` (default DayZ server config shipped with the Pelican DayZ egg; Bohemia's own `serverDZ.cfg` ships only inside the server download, which cannot be fetched anonymously). LF endings, space-only lines, tab-indented comments, `//` comments, no final newline. Its password values are empty. |
| `BEServer_x64.cfg` | `Server_Install_Pack/sc/battleye/example-beserver_x64.cfg` from <https://github.com/EpochModTeam/Epoch> at commit `c4f06bf321a0141f096da5aed461174e09fbb3ed` (a BattlEye example). Its `RConPassword` is the published placeholder `changemen0w`, not a real secret. LF endings. |
| `BEServer_x64.rcon-ip.cfg` | `battleye/BEServer_x64.cfg` from <https://github.com/XxFri3ndlyxX/Battleye-Bec-DayZ-Auto_Restart> at commit `3fc942e81b4ef14f16486b297d3c7afbfd730822`. Its `RConPassword` is the placeholder `CHANGEPASSWORD`. LF endings. |

## Hand-written

| File | Notes |
|---|---|
| `generic.ini` | Hand-written, modelled on common game-server INI files. No public source was used. Has `;` and `#` comments, top-level keys before the first section, `key = value` and `key=value` styles, an empty value, a quoted value, a dotted section name and a backslash path. |

## Derived variants

| File | Derived from | Change |
|---|---|---|
| `serverDZ.crlf.cfg` | `serverDZ.cfg` | every line ending turned into CRLF (still no final newline) |
| `serverDZ.bom.cfg` | `serverDZ.cfg` | UTF-8 BOM prepended |
| `cfggameplay.crlf.json` | `cfggameplay.json` | every line ending turned into CRLF |
| `cfggameplay.bom.json` | `cfggameplay.json` | UTF-8 BOM prepended |
| `cfggameplay.trailing-ws.json` | `cfggameplay.json` | trailing space after each line-ending comma, tab after each line-ending `{` |
| `BEServer_x64.crlf.cfg` | `BEServer_x64.cfg` | CRLF endings |
| `BEServer_x64.bom.cfg` | `BEServer_x64.cfg` | UTF-8 BOM prepended |
| `BEServer_x64.trailing-ws.cfg` | `BEServer_x64.cfg` | trailing spaces/tab on the `RConPort`, `MaxPing` and `Max*Interval` lines |
| `generic.crlf.ini` | `generic.ini` | CRLF endings |
| `generic.bom.ini` | `generic.ini` | UTF-8 BOM prepended |
| `generic.trailing-ws.ini` | `generic.ini` | two trailing spaces on every non-blank line |
| `generic.mixed-eol.ini` | none (hand-written) | tiny INI with mixed CRLF/LF endings and no final newline |

## Formats each file is valid in

The round-trip test keeps this mapping in code
(`round_trip_preservation_test.dart`): `serverDZ*.cfg` is `dayz-cfg`,
`cfggameplay*.json` is `json`, `BEServer_x64*.cfg` is `kv`, `generic*.ini` is
`ini` (and `kv`, which accepts any line of words). Files with a BOM or CRLF are
valid in the same formats as their source.
