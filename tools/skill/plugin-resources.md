# Portable shared-resource contract

Installed Tron skills and their shared tools must live under one package root:

```text
<plugin-root>/skills/<skill>/SKILL.md
<plugin-root>/tools/...
```

The `resourceContract` object in both plugin manifests is the machine-readable source of truth.
`schemaVersion: 1` means each `skills.<name>` value is the complete list of root-relative files or
directories an installer must materialize with that skill. Paths keep their repository layout beneath
the declared `root` (`.`). Installers must not flatten them or infer dependencies from Markdown links.

At runtime, use `tools/skill/resolve-plugin-root.sh`. It accepts the skill name followed by every exact
path the current operation requires. It prefers `TRON_PLUGIN_ROOT`, honors the Claude compatibility
variables, derives the root from its own installed location, then searches supported Claude, Codex,
OpenCode, and Tron release-store locations. A partial installation fails with the missing path and an
install/update instruction.

`TRON_PLUGIN_ROOT` is the harness-neutral explicit override. A harness that does not materialize the
declared tree must populate it with the absolute package root. Never continue with raw Markdown when the
ADF converter is unavailable.
