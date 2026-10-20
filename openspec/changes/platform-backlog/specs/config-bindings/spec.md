# Spec Delta

## Purpose

Applies instance settings to game configuration files declared by the plugin, preserving everything the admin or the game wrote that Yagura does not own.

## ADDED Requirements

### Requirement: Supported formats
The daemon SHALL support the formats `json`, `ini` (sections, `key=value`, `;` and `#` comments), `ue-ini` (Unreal: sections, repeated keys, `+`/`-` prefixed array entries, struct values in parentheses), `xml` (element and attribute paths), `vdf`, `dayz-cfg` (class blocks, `key = value;`, arrays in braces) and `kv` (one `key value` or `key=value` per line).

#### Scenario: Array value in dayz-cfg
- **WHEN** a `string_list` setting `motd: ["Welcome", "Have fun"]` is bound to `serverDZ.cfg` key `motd`
- **THEN** the file contains `motd[] = {"Welcome", "Have fun"};`

#### Scenario: Repeated UE keys from a list setting
- **WHEN** an ARK:SA `list` setting `itemStackOverrides` with two rows is bound to `Game.ini` `[/script/shootergame.shootergamemode]` key `ConfigOverrideItemMaxQuantity` with mode `repeat`
- **THEN** the section contains exactly two `ConfigOverrideItemMaxQuantity=(ItemClassString="...",Quantity=(MaxItemQuantity=...))` lines in row order and no other lines of that key

#### Scenario: Unknown format name
- **WHEN** a manifest binding declares `format: toml`
- **THEN** the plugin is `rejected` at load with an error listing the supported formats
