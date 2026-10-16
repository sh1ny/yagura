# Spec Delta

## Purpose

Ensures only devices the admin paired can control a daemon, over an encrypted and mutually authenticated channel, and that secrets held by the daemon never leave it.

## ADDED Requirements

### Requirement: Development mode is localhost only
The daemon SHALL serve plaintext gRPC only when started with `--dev` and SHALL bind it only to a loopback address; starting dev mode with any other bind address fails.

#### Scenario: Dev mode on loopback
- **WHEN** the daemon starts with `--dev --bind 127.0.0.1:7443`
- **THEN** a plaintext listener is open on 127.0.0.1 and the console warns `DEV MODE: unauthenticated, localhost only`

#### Scenario: Dev mode on a public address
- **WHEN** the daemon starts with `--dev --bind 0.0.0.0:7443`
- **THEN** it exits with a non-zero code and the error `dev_mode_requires_loopback`
