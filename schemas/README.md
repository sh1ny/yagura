# schemas

JSON Schemas for plugin-shaped documents.

- `plugin-manifest.v1.json`: structure of `plugin.yaml` for `manifest_version: 1` (documented in `docs/plugins/manifest.md`).

`packages/yagura_plugin` embeds a copy in `lib/src/manifest_schema.g.dart` so the loader works without this checkout. After editing the schema, regenerate it from `packages/yagura_plugin` with `dart run tool/embed_schema.dart`; a test fails when the copy is stale.
