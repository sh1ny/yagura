# Spec Delta

## Purpose

Controls who can reach a daemon's API. This version serves only an unauthenticated development connection restricted to the local machine.

## ADDED Requirements

### Requirement: Development mode is localhost only
The daemon SHALL serve plaintext gRPC only when started with `--dev` and SHALL bind it only to loopback addresses (`127.0.0.1`, `::1`, or `localhost` when every address it resolves to is loopback), by default `127.0.0.1:7443`; starting dev mode with any other bind address fails. In this version the daemon has no authenticated listener, so starting it without `--dev` fails.

#### Scenario: Dev mode on loopback
- **WHEN** the daemon starts with `--dev --bind 127.0.0.1:7443`
- **THEN** a plaintext listener is open on 127.0.0.1 and the console warns `DEV MODE: unauthenticated, localhost only`

#### Scenario: Dev mode on a public address
- **WHEN** the daemon starts with `--dev --bind 0.0.0.0:7443`
- **THEN** it exits with a non-zero code and the error `dev_mode_requires_loopback`

#### Scenario: Dev mode default bind
- **WHEN** the daemon starts with `--dev` and no `--bind`
- **THEN** it listens on `127.0.0.1:7443` only

#### Scenario: Started without dev mode
- **WHEN** the daemon starts without `--dev`
- **THEN** it exits non-zero with `secure_mode_unavailable` and opens no listener
