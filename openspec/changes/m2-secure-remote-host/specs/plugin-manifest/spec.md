# Spec Delta

## ADDED Requirements

### Requirement: Secret settings are write-only
A `default` on a `secret` setting SHALL be rejected at load. A secret value SHALL enter only through `SetSecret`, be stored in the secret store and never be returned: reads give `{"secret": true, "set": <bool>}`. In other calls either placeholder or an omitted key leaves the stored value unchanged, and a value fails with `INVALID_ARGUMENT` reason `secret_via_set_secret`. `DeleteSecret` clears it.

#### Scenario: Secret values are write-only
- **WHEN** a client reads the settings of an instance with a `secret` setting that has a value
- **THEN** the field is returned as `{"secret": true, "set": true}` and the value is not returned

#### Scenario: Settings saved with the secret placeholder
- **WHEN** a client saves settings it read from the daemon, with a changed port and the secret field still `{"secret": true, "set": true}`
- **THEN** the save succeeds, the port is changed, and the stored secret value is unchanged

#### Scenario: Secret value in a settings save
- **WHEN** a client calls `UpdateSettings` with a plain value for a `secret` setting
- **THEN** the call fails with `INVALID_ARGUMENT` reason `secret_via_set_secret`, and nothing is saved

#### Scenario: Secret value in a create
- **WHEN** a client calls `CreateInstance` with a plain value for a `secret` setting
- **THEN** the call fails with `INVALID_ARGUMENT` reason `secret_via_set_secret`, and no instance is created

#### Scenario: Secret cleared
- **WHEN** a client calls `DeleteSecret` for a secret setting that has a value
- **THEN** the value is removed from the secret store and reads return `{"secret": true, "set": false}`

#### Scenario: Default on a secret rejected
- **WHEN** a manifest declares `default: "changeme"` on a `secret` setting
- **THEN** the plugin is `rejected` at load with an error naming the setting

### Requirement: Required secrets are checked at start
An instance SHALL be created without its secret values. Start SHALL fail with `FAILED_PRECONDITION` reason `secret_required` naming any `required` secret setting that is unset.

#### Scenario: Required secret unset at start
- **WHEN** a client starts an instance whose `required` secret setting `rcon_password` is unset
- **THEN** the call fails with `FAILED_PRECONDITION` reason `secret_required` naming `rcon_password`, and the state is unchanged

#### Scenario: Required secret set
- **WHEN** a client sets `rcon_password` with `SetSecret` and then starts the instance
- **THEN** the start proceeds past the settings check

## REMOVED Requirements

### Requirement: Secret settings stay unset without a secret store
**Reason**: M2 adds the OS-backed secret store, so secret values are accepted and stored there (daemon-security, Secrets never leave the daemon).
**Migration**: Secret settings start unset on upgraded daemons, because M1 never stored a value; admins set them after upgrading. The load-time rejection of a `default` and the placeholder rules move to "Secret settings are write-only".
