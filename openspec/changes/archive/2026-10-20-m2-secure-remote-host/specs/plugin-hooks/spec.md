# Spec Delta

## MODIFIED Requirements

### Requirement: Hook input and output contract
Each hook SHALL receive one JSON context (instance id, plugin id and version, OS, paths relative to the instance root, settings with secrets replaced by placeholders, ports) and SHALL return a JSON object validated against that hook's result schema; unknown keys are rejected. A secret value never reaches a hook.

#### Scenario: Context contents
- **WHEN** `onPreStart` runs for an instance whose plugin declares a `secret` setting `rconPassword` and no value is set
- **THEN** the context contains `settings.rconPassword` as `{"secret": true, "set": false}` and no other value for it

#### Scenario: Context with a secret set
- **WHEN** `onPreStart` runs for an instance with an RCON password set
- **THEN** the context contains `settings.rconPassword` as `{"secret": true, "set": true}` and not the password

#### Scenario: Invalid result shape
- **WHEN** `onPreStart` returns `{"args": "-freezecheck"}` (a string instead of an array)
- **THEN** the operation fails with error `hook_result_invalid` naming `onPreStart` and the path `args`, and the server is not started
