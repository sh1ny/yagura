# yagurad integration tests

Tests against the real OS: the installed service, local accounts, ACLs, the admin pipe and the real Windows Firewall. Most are tagged `elevated` and run only in the manual `elevated` workflow (`.github/workflows/elevated.yml`), never on a developer's desktop. `dart test` loads this directory together with `test/` (`paths` in `dart_test.yaml`).
