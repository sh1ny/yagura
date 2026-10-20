# Plugin hooks (`hooks.js`)

A plugin may ship a `hooks.js` next to its `plugin.yaml` ([manifest](manifest.md)). It holds small synchronous JavaScript functions the daemon calls at fixed points of an instance's life, for game-specific steps the manifest cannot express. A hook **decides**; the daemon **does**: a hook returns data (extra launch arguments, environment variables, file edits) and the daemon applies it. Hooks run in a sandbox (quickjs-ng, ADR 0003) that cannot stall the daemon or reach outside the instance.

## How the examples in this document are checked

A test loads this file and runs the examples against a fixture instance. A fenced block tagged ```` ```js hook=<name> ```` is a complete `hooks.js` and is run as that hook. The ```` ```json context ```` block is the context it receives, ```` ```json instance ```` lists the files the fixture instance holds (path to content), and the ```` ```json result ```` block after an example is the exact result the hook must return. Blocks of any other kind are not checked.

The fixture instance and context used by every example:

```json context
{
  "instanceId": "inst-1",
  "pluginId": "dayz",
  "pluginVersion": "1.0.0",
  "os": "windows",
  "paths": { "config": "cfg", "keys": "keys" },
  "settings": {
    "maxPlayers": 60,
    "rconPassword": { "secret": true, "set": false }
  },
  "ports": { "game": 2302 }
}
```

```json instance
{
  "cfg/cfggameplay.json": "{\n  \"version\": 120,\n  \"GeneralData\": {\n    \"disableBaseDamage\": false,\n    \"restartPending\": true\n  }\n}\n",
  "keys/a.bikey": "aaaa",
  "keys/b.bikey": "bbbbbbbb"
}
```

## Writing `hooks.js`

`hooks.js` is a classic script (not an ES module), at most 1 MiB. A hook is found, in this order, as `exports.<name>`, `module.exports.<name>` or a top-level `function <name>`:

```js
exports.onPreStart = function (ctx) {
  return { args: ['-freezecheck'] };
};
```

- A hook that is not exported is skipped without a warning.
- Hooks are synchronous. A hook that returns a promise fails with `hook_error`.
- A hook receives one argument, the context (below), and returns a JSON object, or nothing (an empty result).
- The script runs in a fresh runtime for every call: nothing survives between calls, so no state needs cleaning up.

## Hook points

| Hook | Called | Result keys |
|---|---|---|
| `onPostInstall` | after the daemon installed the instance's game files | `files` |
| `onPostUpdate` | after the daemon updated the game files | `files` |
| `onPreStart` | before the server process starts | `args`, `env`, `files` |
| `onPostStop` | after the server process stopped | `files` |
| `migrateSettings` | after a plugin reload changed the plugin's version, once per instance of the plugin | `settings` |

## Context

Every hook receives the same JSON object:

| Key | Content |
|---|---|
| `instanceId`, `pluginId`, `pluginVersion` | identity of the instance and the plugin |
| `os` | `"windows"` or `"linux"` |
| `paths` | named paths, relative to the instance root, without `..` |
| `settings` | the instance's settings by key; a `secret` setting appears only as `{"secret": true, "set": <bool>}`, never its value |
| `ports` | port numbers by name |
| `fromVersion`, `toVersion` | `migrateSettings` only: the plugin version the instance's settings were saved under, and the loaded one (`pluginVersion` is the loaded one too) |

The serialised context is limited to 1 MiB.

## Result

The result is validated against the hook's schema; **unknown keys are rejected** with `hook_result_invalid`, naming the hook and the path of the offending value (for example `args`, `args[0]`, `env.NAME`, `files[0].format`).

| Key | Type | Meaning |
|---|---|---|
| `args` | array of strings | `onPreStart` only. Appended after the manifest's launch arguments. |
| `env` | object of strings | `onPreStart` only. Added to the server's environment. |
| `files` | array of file edits | Edits the daemon applies, see below. |
| `settings` | object | `migrateSettings` only, and its only key. The instance's complete settings for the new schema; omitted or empty result keeps them as they are. |

A **file edit** is `{"path": string, "format": "json" | "ini" | "dayz-cfg" | "kv", "patch": object}`. The path is relative to the instance root. The patch is an [RFC 7386](https://www.rfc-editor.org/rfc/rfc7386) merge patch: objects merge recursively, `null` removes a key, anything else (arrays included) replaces the value. The daemon keeps the file's key order and formatting, appends new keys in the layout of their neighbours, and creates the file (and its directories) when it does not exist.

For `ini`, `dayz-cfg` and `kv` the patch is a flat object from key path to new value, and a `null` value removes the key: `{"maxPlayers": 40}`, or `{"Section.key": "x"}` for `ini` and `{"class.key": 1}` for `dayz-cfg`. The daemon changes only those keys: comments, blank lines, key order, unknown keys, line endings and the byte order mark of the file stay as they are.

The config binder applies the edits, in one pass with the plugin's `bindings` (see the manifest reference): the bindings first, then the edits in order. It applies all edits of one result or none: it resolves every path and computes every new content first, writes only the files whose bytes change to a temporary file in its directory and moves it over the target with an atomic rename, and restores the files already replaced if a later step fails. An edit whose path is not relative to the instance root, or that passes through a symbolic link or junction (even one that points inside the instance), fails with `sandbox_violation`. A file held open by a running process is retried every 250 ms for 5 s, then the pass fails with `file_locked` and everything is rolled back. The formats are `json`, `ini`, `dayz-cfg` and `kv`; any other fails with `unsupported_in_this_version` naming the path and format, and no file changes. A file that does not parse in its format fails with `config_parse_error`.

### `migrateSettings`

The daemon calls it from a `migrate_settings` operation that a reload queues at the head of each affected instance's queue, so no queued operation runs on the new manifest with unmigrated settings. The context carries the stored settings (secrets as placeholders), and the result's `settings` replace them if they validate against the new schema. The instance then records the new plugin version in the same transaction, which increments its revision and rewrites `instance.json`. Without the hook the stored settings are validated as they are.

A secret setting must come back as the placeholder it was given: a secret value never passes through a hook, and the daemon keeps the stored value. A result that changes a placeholder fails with `hook_result_invalid`.

When the hook throws or the settings do not validate, the stored settings and the recorded version stay as they were and the other instances are still migrated. A stopped instance becomes `error` with `settings_invalid`; a running one keeps running with the `settings_invalid` flag. The notice names the fields or the hook error. Until a valid settings save records the loaded version, every operation of the instance but Stop and delete fails `invalid_state`.

## Host API

Hooks reach the system only through the global `yagura` object. There is no network, process, environment-variable, timer or `console` access, and hooks cannot write files.

| Call | Returns |
|---|---|
| `yagura.log(message)`, `yagura.log(level, message)` | nothing. Level is `debug`, `info` (default), `warn` or `error`. Recorded in the operation history; at most 500 entries of 4096 characters. |
| `yagura.fs.readText(path)` | the file's text (UTF-8). At most 16 MiB. |
| `yagura.fs.list(path)` | array of `{name, size, isDirectory}`. At most 10,000 entries. |
| `yagura.formats.json.parse(text)` | the parsed value; throws `invalid_json` on bad input. At most 16 MiB. |
| `yagura.formats.json.serialize(value, indent?)` | JSON text; `indent` is 0 to 10 spaces. At most 16 MiB. |
| `yagura.formats.ini.get(text, path)`, `yagura.formats['dayz-cfg'].get(text, path)`, `yagura.formats.kv.get(text, path)` | the value at the key path as a string, or `null` when the key is missing; throws `config_parse_error` when the text does not parse. At most 16 MiB. |
| `yagura.formats.ini.edit(text, patch)`, `yagura.formats['dayz-cfg'].edit(text, patch)`, `yagura.formats.kv.edit(text, patch)` | the text with the patch (key path to value, `null` removes) applied and everything else kept. At most 16 MiB. |

Paths must be relative to the instance root. An absolute path, a path with `..`, and a path that passes through a symbolic link or junction (even one that points inside the instance) throw `sandbox_violation` inside the hook; links are never followed and nothing outside is read. `yagura.fs.list` reports a link as an entry of size 0 that is not a directory.

A failing host call throws a JavaScript `Error` whose `code` property is the reason:

| `code` | When |
|---|---|
| `sandbox_violation` | the path is absolute or leaves the instance root, or a symbolic link or junction is on it |
| `host_limit_exceeded` | a read or parse call over 16 MiB, or a listing over 10,000 entries; the message names the limit |
| `not_supported` | any other member of `yagura.fs`, such as `writeText`: `yagura.fs` has no write functions, return file edits instead |
| `unsupported_in_this_version` | `yagura.formats.<format>` for any format but `json`, `ini`, `dayz-cfg` and `kv` |
| `config_parse_error` | `yagura.formats.<format>.get` or `.edit` on text that does not parse in that format |
| `invalid_json` | `yagura.formats.json.parse` on invalid JSON |
| `hook_error` | a call with wrong arguments |
| `ENOENT`, `EISDIR`, `ENOTDIR` | the file or directory does not exist, or is of the wrong kind |

An error a hook does not catch fails the operation, so a hook can let `e.code` surface or handle it:

```js
try {
  text = yagura.fs.readText('cfg/optional.json');
} catch (e) {
  if (e.code !== 'ENOENT') throw e;
}
```

## Limits and failures

| Limit | Value | Failure |
|---|---|---|
| Deadline | 5 s by default, or the manifest's `hooks.timeout_seconds` up to 60 s | `hook_timeout` |
| Heap | 64 MiB | `hook_out_of_memory` |
| Result | 1 MiB serialised | `hook_result_too_large` |
| Script stack | 512 KiB | `hook_error` (`stack overflow`) |
| Concurrent hook workers | 4 per daemon | the call waits; waiting does not count against its deadline |

The deadline stops the script inside the engine (a script cannot catch it) and frees its runtime. If the worker still has not stopped 2 s after the deadline, the call fails with `hook_timeout` anyway and the worker is asked to exit; its slot stays reserved until it has. After 2 workers have failed to exit within 5 s of that point, every hook call fails with `hook_runtime_degraded` until the daemon restarts.

| Failure | Reason | Carries |
|---|---|---|
| `hooks.js` does not parse | `hook_syntax_error` | message and `hooks.js:<line>` |
| a hook throws | `hook_error` | the error's message and its stack, with `hooks.js:<line>:<column>` locations |
| result has the wrong shape | `hook_result_invalid` | hook name and path |
| edit in another format | `unsupported_in_this_version` | path and format |
| edited file does not parse | `config_parse_error` | path, line and column |
| edited file held by a running process | `file_locked` | path |
| edit outside the instance | `sandbox_violation` | path |

## Examples

One example per hook point. Each is run by the test described above.

### `onPostInstall`

Count the server's key files and make sure the damage setting starts enabled.

```js hook=onPostInstall
exports.onPostInstall = function (ctx) {
  const keys = yagura.fs.list(ctx.paths.keys).filter(function (e) {
    return !e.isDirectory;
  });
  yagura.log('info', 'found ' + keys.length + ' key files');
  return {
    files: [{
      path: ctx.paths.config + '/cfggameplay.json',
      format: 'json',
      patch: { GeneralData: { disableBaseDamage: false } }
    }]
  };
};
```

```json result
{
  "files": [
    {
      "path": "cfg/cfggameplay.json",
      "format": "json",
      "patch": { "GeneralData": { "disableBaseDamage": false } }
    }
  ]
}
```

### `onPostUpdate`

Raise the gameplay file's version after an update, only when it is older.

```js hook=onPostUpdate
exports.onPostUpdate = function (ctx) {
  const path = ctx.paths.config + '/cfggameplay.json';
  const current = yagura.formats.json.parse(yagura.fs.readText(path));
  if (current.version >= 122) return {};
  return { files: [{ path: path, format: 'json', patch: { version: 122 } }] };
};
```

```json result
{
  "files": [
    { "path": "cfg/cfggameplay.json", "format": "json", "patch": { "version": 122 } }
  ]
}
```

### `onPreStart`

Add launch arguments and an environment variable from the settings.

```js hook=onPreStart
exports.onPreStart = function (ctx) {
  return {
    args: ['-freezecheck', '-maxPlayers=' + ctx.settings.maxPlayers],
    env: { SteamAppId: '221100' }
  };
};
```

```json result
{
  "args": ["-freezecheck", "-maxPlayers=60"],
  "env": { "SteamAppId": "221100" }
}
```

### `onPostStop`

Clear a flag the server left in its gameplay file (`null` removes a key).

```js hook=onPostStop
exports.onPostStop = function (ctx) {
  return {
    files: [{
      path: ctx.paths.config + '/cfggameplay.json',
      format: 'json',
      patch: { GeneralData: { restartPending: null } }
    }]
  };
};
```

```json result
{
  "files": [
    {
      "path": "cfg/cfggameplay.json",
      "format": "json",
      "patch": { "GeneralData": { "restartPending": null } }
    }
  ]
}
```

### `migrateSettings`

Move a renamed setting to its new key (`ctx.fromVersion` and `ctx.toVersion` name the versions; secrets are placeholders and stay as they are).

```js hook=migrateSettings
exports.migrateSettings = function (ctx) {
  const settings = Object.assign({}, ctx.settings);
  settings.maxPlayers = Math.min(settings.maxPlayers, 40);
  return { settings: settings };
};
```

```json result
{
  "settings": {
    "maxPlayers": 40,
    "rconPassword": { "secret": true, "set": false }
  }
}
```
