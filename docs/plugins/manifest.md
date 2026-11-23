# Plugin manifest (`plugin.yaml`, version 1)

A game is described to Yagura as data: a folder under the daemon's plugins directory holding a `plugin.yaml` and, optionally, a `hooks.js` (see [hooks](hooks.md)). The daemon validates the manifest when it loads the plugin and lists the plugin as `loaded` or `rejected` with the reasons. A rejected plugin cannot be used for new instances.

The structure is defined by [`schemas/plugin-manifest.v1.json`](../../schemas/plugin-manifest.v1.json) (JSON Schema draft-07). The schema covers structure; the loader adds the checks a schema cannot express (template references, derived ports, regular expressions, paths staying inside the instance, features this version refuses).

Check a plugin without starting the daemon:

```text
dart run bin/yagura.dart plugin lint <plugin directory>   # from packages/yagura_plugin
```

The command prints `<id>: loaded` and exits 0, or prints every error as `plugin.yaml:<line>: [<reason>] <field path>: <message>` and exits 1.

## How the examples in this document are checked

A test lints this file. A fenced block tagged ```` ```yaml ```` is a **complete manifest** and must load. A block tagged ```` ```yaml fragment ```` is a **partial snippet**: it is not a manifest, and the test only checks that it is valid YAML. Blocks of any other kind are not checked.

## Limits

| Limit | Value | Reason when exceeded |
|---|---|---|
| `plugin.yaml` size | 256 KiB | `file_too_large` |
| `hooks.js` size | 1 MiB | `file_too_large` |

Sizes are checked before the file is parsed.

## Reasons a plugin is rejected

| Reason | Meaning |
|---|---|
| `unsupported_manifest_version` | `manifest_version` is not one of the supported versions (currently `[1]`); the error lists them. |
| `file_too_large` | `plugin.yaml` or `hooks.js` is over its limit; the error names the file and the limit. |
| `unsupported_in_this_version` | The manifest uses something this release refuses, naming the field: an `rcon` section, `mods.source: url_archive`, `stop.strategy: rcon`, `health.type: query`, or a binding in the format `ue-ini`, `xml` or `vdf`. |
| `invalid_manifest` | Anything else: YAML syntax, a schema violation (with the allowed values), an unknown template reference, a bad regular expression, a data path outside the instance, a binding that names an undeclared setting or an unknown format, a binding file outside the instance, a secret or a mod role used outside its namespace, a `mods` section whose source and stage mode do not fit or whose directories leave the instance, a `steam.gslt` that does not name a secret setting. |

Every error carries the field path (`ports[0].protocol`) and the line of the offending value in `plugin.yaml`.

## Fields, with the Valheim manifest as the walkthrough

The complete Valheim manifest is at the end of this section. Each part is introduced first.

### Identity

```yaml fragment
manifest_version: 1
id: valheim
name: Valheim Dedicated Server
version: 0.1.0
description: Valheim dedicated server through anonymous SteamCMD.
```

| Field | Required | Meaning |
|---|---|---|
| `manifest_version` | yes | Integer. Only `1` is supported. |
| `id` | yes | Stable identifier: lowercase letters, digits, `_` and `-`, starting with a letter, at most 64 characters. |
| `name` | yes | Display name. |
| `version` | yes | Plugin version, free-form text. |
| `description` | no | Free text. |

### `steam`

```yaml fragment
steam:
  app_id: 896660
  login: anonymous
  size_hint_bytes: 1500000000
  gslt: { setting: gslt, required: true }
```

| Field | Required | Meaning |
|---|---|---|
| `app_id` | yes | Steam application id of the dedicated server. |
| `login` | no | `anonymous` (default), `account_optional` (installed with the anonymous login in this version) or `account` (refused with `steam_account_required` until Steam accounts exist). |
| `size_hint_bytes` | no | Approximate install size, used to warn about disk space before installing. |
| `gslt` | no | `{ setting: <name>, required: <bool> }`: the `secret` setting that holds the instance's Game Server Login Token. `setting` must name a declared top-level secret setting, or the plugin is rejected. With `required: true` a Start while the token is unset fails `gslt_required` (checked before `secret_required`), and no process is launched. The launch arguments hand it to the server as `{{secrets.<setting>}}`; it is never used as a Steam account login. |

The whole section is optional for games that are not installed through Steam.

### `executable`

```yaml fragment
executable:
  windows: valheim_server.exe
  linux: valheim_server.x86_64
```

The server executable per OS, relative to the server install directory. At least one OS is required. The executable must be the process that runs for the server's whole lifetime: a launcher that exits after spawning the real server is not supported. The server starts with the install directory as its working directory, so files the game looks up relative to it (such as Steam's `steam_appid.txt`) are found.

A plugin that declares only `linux` loads with `platforms: [linux]`; creating an instance of it on Windows is refused by the daemon (`unsupported_platform`), not at load.

### `ports`

```yaml fragment
ports:
  - name: game
    default: 2456
    protocol: udp
    purpose: game
  - name: query
    derive: { from: game, offset: 1 }
    protocol: udp
    purpose: query
```

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | Lowercase identifier, unique in the plugin. Referenced as `{{ports.<name>}}`. |
| `default` | one of `default` or `derive` | Default port number, 1-65535. |
| `derive` | one of `default` or `derive` | `{ from: <port name>, offset: <integer> }`: the port is the resolved number of another port plus the offset. `from` must name a port that has a `default`. |
| `protocol` | yes | `udp`, `tcp` or `both`. |
| `purpose` | yes | `game`, `query`, `rcon`, `web` or `other`. |
| `exposed` | no | Whether the firewall opens the port. Default `true`; default `false` for `purpose: rcon`. |

With the Valheim declaration above, an instance that sets `game` to 2466 gets `query` 2467.

### `settings`

A map from setting name to its definition. The daemon serves this schema to the client, which renders the form, and validates values against it.

```yaml fragment
settings:
  serverName:
    type: string
    label: Server name
    default: Yagura Valheim
    min: 1
    max: 64
    group: General
  worldName:
    type: string
    label: World name
    default: Dedicated
    pattern: "^[A-Za-z0-9_]+$"
    group: General
  password:
    type: secret
    label: Server password
    group: General
```

Setting names start with a letter and use letters, digits and `_`.

| Attribute | Meaning |
|---|---|
| `type` | Required. One of `string`, `integer`, `number`, `boolean`, `enum`, `secret`, `string_list`, `object`, `list`. |
| `label`, `description` | Text for the form. |
| `default` | Value used when none is set. Must itself be valid for the setting. **Rejected on `secret`.** |
| `required` | Boolean. A required setting with no default must be given a value. |
| `min`, `max` | `string`: length. `integer`, `number`: value. `string_list` and `list`: item count. |
| `pattern` | `string` only: a regular expression the value must match (not anchored unless you anchor it). Checked as a valid regular expression at load. |
| `group` | Form section the setting is shown in. |
| `advanced` | Boolean; hides the setting behind an "advanced" toggle. |
| `values` | `enum` only, required: the allowed strings. |
| `fields` | `object` and `list`, required: the nested settings (for `list`, the columns of one row). |

Types:

| Type | Value |
|---|---|
| `string` | text |
| `integer` | whole number |
| `number` | any number |
| `boolean` | `true` or `false` |
| `enum` | one of `values` |
| `secret` | write-only; see below |
| `string_list` | ordered list of strings |
| `object` | a map with the declared `fields` |
| `list` | an ordered array of rows, each an object with the declared `fields` |

A repeatable structure, as an ARK: Survival Ascended plugin would declare it:

```yaml fragment
settings:
  itemStackOverrides:
    type: list
    label: Item stack overrides
    fields:
      class: { type: string, required: true }
      max: { type: integer, min: 1 }
```

Two rows are accepted and kept as an ordered array. A row that omits `class` fails with an error naming `itemStackOverrides[1].class` (for the second row).

**Secrets.** A `secret` setting is a top-level setting: a `secret` field inside an `object` or `list` setting rejects the plugin at load, with an error naming the dotted path (`servers.password`). It is write-only. Its value is set with `SetSecret`, stored in the daemon's secret store and cleared with `DeleteSecret`. It is never returned: reads, the hook context and `instance.json` show `{"secret": true, "set": true}` or `{"secret": true, "set": false}` (`instance.json` shows `{"secret": true}`). When settings are saved, the placeholder or an omitted key leaves the stored value unchanged, and a plain value is refused with `secret_via_set_secret`. A `default` on a `secret` rejects the plugin at load, with an error naming the setting. An instance is created without its secrets, so `required: true` on a secret is checked at Start: it fails `secret_required` naming the setting until the secret is set.

**Schema version.** The settings schema has a version: the first 32 bits of the SHA-256 of the canonical JSON of the `settings` section, read as a big-endian unsigned integer. Canonical JSON has object keys sorted by code unit at every level, no whitespace, array order kept, and strings escaped as `dart:convert` writes them. Any change to the schema, including a default or a constraint, changes the version, so a form opened before a plugin reload cannot write stale fields. Changes outside `settings` do not change it.

### `launch`

```yaml fragment
launch:
  args:
    - -nographics
    - -batchmode
    - -name
    - "{{settings.serverName}}"
    - -port
    - "{{ports.game}}"
    - -world
    - "{{settings.worldName}}"
    - -savedir
    - "{{instance}}/save"
    - -logFile
    - "{{instance}}/logs/server.log"
    - -public
    - "0"
```

`launch.args` is a list of entries. The daemon renders them when the instance starts into an argument list and starts the executable with that list directly: no shell is involved, so a setting value containing spaces, quotes or `;` stays one argument and cannot inject another.

An entry is one of:

1. **A string.** A template rendering to exactly one argument.
2. **A conditional group** `{ when: <reference>, args: [...] }` or `{ unless: <reference>, args: [...] }`. The nested entries (any kind) are rendered only if the reference is a `boolean` setting that is `true` (`when`) or is not `true` (`unless`). An unset boolean counts as not true.
3. **A join** `{ join: { list: <reference>, separator: <text>, prefix: <text> } }`, optionally with `when` or `unless`. `list` is a `string_list` setting; the entry renders to one argument, `prefix` followed by the items joined by `separator`. An empty list renders nothing. `prefix` and `separator` are literal text.

```yaml fragment
launch:
  args:
    - -config=serverDZ.cfg
    - when: settings.logs
      args: [-dologs, -adminlog, -netlog]
    - join: { list: settings.serverMods, separator: ";", prefix: "-mod=" }
```

With `logs: true` and `serverMods: ["@CF", "@VPP"]` this renders `-config=serverDZ.cfg`, `-dologs`, `-adminlog`, `-netlog` and `-mod=@CF;@VPP`, each a separate argument.

**Templates.** Inside a string, `{{reference}}` is replaced by a value. There are no other expressions and no escape for a literal `{{`. References:

| Reference | Value |
|---|---|
| `settings.<name>` (or `settings.<object>.<field>`) | A setting's value. Only scalar settings (`string`, `integer`, `number`, `boolean`, `enum`) can be written into a string; use `join` for a `string_list`. |
| `ports.<name>` | The resolved port number. |
| `paths.instance`, `paths.server` | The instance directory and the server install directory. |
| `instance` | Shorthand for `paths.instance`. |
| `os` | `windows` or `linux`. |
| `secrets.<setting>` | The value of a top-level `secret` setting. Only in `launch.args`, and only for secret settings: `{{settings.<secret>}}` and `{{secrets.<non-secret>}}` both reject the plugin. At most one secret per argument. An argument whose secret is unset is left out. |
| `mods.<role>` | The instance's mods of one role, in load order. Only as the `list` of a `join` in `launch.args`. A role the `mods` section does not declare rejects the plugin. |

**Secrets reach only the server.** The value of a `secrets` reference travels from the daemon to the launcher and on to the relay over standard input, and is put into the server's command line in memory just before the server starts. It is never written to a file: `launch.json` records `{"secret": "<setting>", "prefix": ..., "suffix": ...}` for the argument, and every argument list the daemon logs or reports shows `***` in its place. A launch whose input line is missing or unreadable fails `launch_input_missing` and starts nothing.

```yaml fragment
launch:
  args:
    - "-gslt={{secrets.gslt}}"
    - join: { list: mods.client, separator: ";", prefix: "-mod=" }
    - join: { list: mods.server, separator: ";", prefix: "-serverMod=" }
```

With client mods `[@CF, @VPP]` and server mods `[@VPPAdminTools]` this renders `-mod=@CF;@VPP` and `-serverMod=@VPPAdminTools` as separate arguments; an empty role renders no argument.

All references are checked when the plugin loads. A template that uses `{{settings.doesNotExist}}` rejects the plugin with an error naming the template and the unknown path, instead of failing at start.

### `stop`

```yaml fragment
stop:
  strategy: signal
  grace_seconds: 30
```

| Field | Meaning |
|---|---|
| `strategy` | `signal` (ask the process to stop, then kill it after the grace period) or `kill`. `rcon` is reserved and rejected in this version. |
| `grace_seconds` | Seconds to wait after the stop request. Default 30. |

### `health`

```yaml fragment
health:
  type: log_match
  log_match: "Game server connected"
  source: server
  start_timeout_seconds: 180
```

| Field | Meaning |
|---|---|
| `type` | `process` (the process is alive; the default), `port` (a declared port is listening) or `log_match`. `query` is reserved and rejected in this version. |
| `port` | For `type: port`: the name of a declared port. |
| `log_match` | For `type: log_match`: a regular expression. It matches only lines written after the current start, so a line left over from the previous run does not count. An invalid expression rejects the plugin with an error naming `health.log_match` and the regular-expression error. |
| `source` | For `type: log_match`: the name of a declared log source. |
| `start_timeout_seconds` | How long to wait for the instance to become healthy. Default 120. |

### `logs`

```yaml fragment
logs:
  - name: server
    path: "logs/server.log"
    encoding: utf-8
    rotation: fixed
```

| Field | Meaning |
|---|---|
| `name` | Lowercase identifier, unique in the plugin; referenced by `health.source`. |
| `path` | A file source: a templated path inside the instance directory (same rules as `data_paths`). Wildcards `*` and `?` are allowed in the file name only, for example `{{instance}}/profiles/*.RPT`. |
| `stdout` | `true` for a stdout capture: the server's standard output and error, captured by the daemon into rotating files (10 MiB, 5 files). Declare exactly one of `path` and `stdout`. |
| `encoding` | `utf-8` (default), `utf-16le` or `latin-1`. Undecodable bytes become U+FFFD. |
| `rotation` | File sources only: `fixed` (follows one path across truncation; default) or `newest` (follows the most recently created matching file). Not allowed with `stdout`. |

A stdout source looks like this:

```yaml fragment
logs:
  - name: console
    stdout: true
```

### `data_paths`

```yaml fragment
data_paths:
  - "save/"
```

Templated paths of save and player data, used for backups. Each must resolve **inside the instance directory**, so plugins pass the game's save-directory argument where needed: Valheim declares `data_paths: ["save/"]` and launches with `-savedir {{instance}}/save`, so both resolve to the instance's `save/` directory.

A relative path is taken from the instance directory; `/` and `\` both separate segments. Only `instance`, `paths.*` and `os` can be referenced (settings and ports cannot, so a setting value cannot move a path). A path that resolves outside the instance directory, to the instance directory itself, or to another drive or root, rejects the plugin with an error naming the path, for example `{{instance}}/../shared`.

### `hooks`

```yaml fragment
hooks:
  timeout_seconds: 10
```

Optional. `timeout_seconds` (`hooks.timeout_seconds` as a field path) is the deadline of each hook call in `hooks.js`: 5 seconds by default, at most 60. A larger value rejects the plugin, naming `hooks.timeout_seconds` and the 60 s maximum. See [hooks](hooks.md) for what hooks can do.

### `bindings`

```yaml fragment
bindings:
  - file: yagura/serverDZ.cfg
    format: dayz-cfg
    key: maxPlayers
    setting: maxPlayers
    create: true
    template: templates/serverDZ.cfg
  - file: yagura/serverDZ.cfg
    format: dayz-cfg
    key: hostname
    setting: hostname
  - file: "{{paths.server}}/battleye/BEServer_x64.cfg"
    format: kv
    key: RConPassword
    setting: rconPassword
    game_writes: true
```

Optional. Each entry writes one setting to one key of one file, every time the instance starts and after an update. The daemon is the only writer of these files: it keeps the comments, blank lines, key order, unknown keys, line endings and encoding of the file, changes only the bound keys, and writes only files whose bytes change (see the config binder in the daemon design).

| Field | Required | Meaning |
|---|---|---|
| `file` | yes | Path of the file relative to the instance directory, as a template over `settings`, `ports`, `paths` and `os` (not secret settings). It must resolve inside the instance directory; a value that moves it outside fails the start with `sandbox_violation`. |
| `format` | yes | `json`, `ini`, `dayz-cfg` or `kv`. `ue-ini`, `xml` and `vdf` are refused with `unsupported_in_this_version`; any other name is rejected with an error listing the supported formats. All bindings of one file must use the same format. |
| `key` | yes | The key path in the file: dotted for `json` (`GeneralData.disableBaseDamage`), for `ini` (`section.key`) and for `dayz-cfg` (`class.key`); the plain key for `kv`. |
| `setting` | yes | The top-level setting whose value is written, a scalar, enum, secret or `string_list` setting. A name the manifest does not declare rejects the plugin, naming the binding and the setting. A secret is read from the secret store only when the binding is applied. A setting without a value is not written. |
| `create` | no | `true` creates the file when it does not exist (from `template`, or empty). Without it a missing file fails the start with `binding_file_missing`, naming the file and the binding. |
| `template` | no | A file in the plugin directory (`templates/serverDZ.cfg`) that a created file starts from. It must exist and stay inside the plugin directory. |
| `game_writes` | no | `true` when the game rewrites the file itself. A change made since the last apply is then not reported as an `external_edit` warning. |

A plugin may bind at most 64 distinct files. A hand edit to a bound key is overwritten at the next start and reported as an `external_edit` warning on the operation, naming each key with its old and new value (`***` for keys bound to secret settings); a hand edit to any other key is kept.

### `mods`

```yaml fragment
mods:
  source: steam_workshop
  workshop_app_id: 221100
  stage: link
  stage_dir: server
  link_name: "@{{mod.name_safe}}"
  copy_fallback: true
  keys:
    - { from: "**/*.bikey", to: server/keys/ }
  roles: [client, server]
```

Optional. Declares that instances of the plugin have mods, where they come from, how they reach the server, and in which lists they are ordered. A plugin without `mods` rejects mod operations with `mods_not_supported`.

| Field | Required | Meaning |
|---|---|---|
| `source` | yes | `steam_workshop` (downloaded through SteamCMD into a store shared by all instances) or `server_managed` (the server fetches its own mods; nothing is downloaded or staged, and the role lists carry the item ids). `url_archive` is refused with `unsupported_in_this_version` naming `mods.source`. |
| `workshop_app_id` | `steam_workshop` | The Steam app the workshop items belong to (`221100` for DayZ). |
| `stage` | no | `link` (a directory link to the shared content; the default for `steam_workshop`), `copy`, or `none` (the only mode of `server_managed`). |
| `stage_dir` | no | Where links or copies are made, relative to the instance directory. Default `server`. It must stay inside the instance. |
| `link_name` | no | Template of a staged mod's name. `{{mod.name_safe}}` is its sanitised workshop title (or `@<item id>` when the title is not available); it is the only reference. It must name one directory. Default `{{mod.name_safe}}`. |
| `copy_fallback` | no | `true` copies a mod whose link cannot be created (for example on a network share). Default `false`: the step fails `stage_link_failed`. |
| `keys` | no | Rules `{ from, to }` applied after staging: files of a staged mod matching the glob `from` (such as `**/*.bikey`) are placed in the directory `to`, relative to the instance and inside it. A key is removed only when no staged mod provides it, and one the daemon did not place is never overwritten. |
| `roles` | yes | The roles a mod can have, such as `[client, server]`: lowercase names, at least one, each once. Each role is a list in the launch templates (`mods.<role>`). |

Every path in the manifest is relative to the instance directory, while launch arguments resolve against the server's working directory, `<instance>/server`. A plugin whose `stage_dir` is not `server` therefore prefixes the relative path in its launch template.

### Reserved sections

`rcon` is reserved for a later version. In this version a manifest that has it is rejected with `unsupported_in_this_version` naming the section, like `stop.strategy: rcon` and `health.type: query`.

### The complete Valheim manifest

```yaml
manifest_version: 1
id: valheim
name: Valheim Dedicated Server
version: 0.1.0
description: Valheim dedicated server through anonymous SteamCMD.

steam:
  app_id: 896660
  login: anonymous
  size_hint_bytes: 1500000000

executable:
  windows: valheim_server.exe
  linux: valheim_server.x86_64

ports:
  - name: game
    default: 2456
    protocol: udp
    purpose: game
  - name: query
    derive: { from: game, offset: 1 }
    protocol: udp
    purpose: query

settings:
  serverName:
    type: string
    label: Server name
    default: Yagura Valheim
    min: 1
    max: 64
    group: General
  worldName:
    type: string
    label: World name
    default: Dedicated
    pattern: "^[A-Za-z0-9_]+$"
    group: General
  password:
    type: secret
    label: Server password
    group: General

launch:
  args:
    - -nographics
    - -batchmode
    - -name
    - "{{settings.serverName}}"
    - -port
    - "{{ports.game}}"
    - -world
    - "{{settings.worldName}}"
    - -savedir
    - "{{instance}}/save"
    - -logFile
    - "{{instance}}/logs/server.log"
    - -public
    - "0"

stop:
  strategy: signal
  grace_seconds: 30

health:
  type: log_match
  log_match: "Game server connected"
  source: server
  start_timeout_seconds: 180

logs:
  - name: server
    path: "logs/server.log"
    encoding: utf-8
    rotation: fixed

data_paths:
  - "save/"
```

## A second complete example

A Windows-only plugin with a boolean that adds arguments and a mod list that is joined:

```yaml
manifest_version: 1
id: dayz
name: DayZ Server
version: 0.1.0

executable:
  windows: DayZServer_x64.exe

settings:
  logs: { type: boolean, default: false }
  serverMods: { type: string_list, label: Server mods }

launch:
  args:
    - -config=serverDZ.cfg
    - when: settings.logs
      args: [-dologs, -adminlog, -netlog]
    - join: { list: settings.serverMods, separator: ";", prefix: "-mod=" }
```

## A third complete example

A DayZ-style plugin: a Game Server Login Token handed to the server as a secret argument, a bound configuration file, and workshop mods in two roles:

```yaml
manifest_version: 1
id: dayz
name: DayZ
version: 0.1.0
steam:
  app_id: 223350
  login: account
  gslt: { setting: gslt, required: false }
executable:
  windows: DayZServer_x64.exe
ports:
  - name: game
    default: 2302
    protocol: udp
    purpose: game
settings:
  hostname: { type: string, default: DayZ }
  maxPlayers: { type: integer, default: 60, min: 1, max: 127 }
  rconPassword: { type: secret }
  gslt: { type: secret }
bindings:
  - file: server/yagura/serverDZ.cfg
    format: dayz-cfg
    key: hostname
    setting: hostname
    create: true
mods:
  source: steam_workshop
  workshop_app_id: 221100
  stage: link
  stage_dir: server
  link_name: "@{{mod.name_safe}}"
  copy_fallback: true
  keys:
    - { from: "**/*.bikey", to: server/keys/ }
  roles: [client, server]
launch:
  args:
    - -config=yagura/serverDZ.cfg
    - "-port={{ports.game}}"
    - join: { list: mods.client, separator: ";", prefix: "-mod=" }
    - join: { list: mods.server, separator: ";", prefix: "-serverMod=" }
    - "-gslt={{secrets.gslt}}"
```
