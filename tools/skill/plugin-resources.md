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
The role/repo package builder consumes this map directly and unions each included skill's declared paths
into the copied resource closure; package-map resource lists are not required to repeat the contract.

At runtime, use `tools/skill/resolve-plugin-root.sh`. It accepts the skill name followed by every exact
path the current operation requires. It prefers `TRON_PLUGIN_ROOT`, honors the Claude compatibility
variables, and otherwise validates the package root that contains the resolver. OpenCode skills bind to
their known `$HOME/.config/opencode` package root. With no exported root, Claude, Codex, and release-store
bootstraps bind only when exactly one installed package contains the invoking skill; multiple copies are
ambiguous and require `TRON_PLUGIN_ROOT`. The resolver never selects tools from a different installation:
a partial package fails with the missing path and an install/update instruction.

`TRON_PLUGIN_ROOT` is the harness-neutral explicit override. A harness that does not materialize the
declared tree must populate it with the absolute package root. Never continue with raw Markdown when the
ADF converter is unavailable.

The resource contract describes packaged files, not host executables. These Jira workflows require
`bash`, `node`, `jq`, and `acli` at runtime. Repository tests additionally use `rg` and `trash`; CI installs
those test-only tools, and installed skills do not call them.
