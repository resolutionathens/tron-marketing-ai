# `evaluate`: the skill evaluation harness

The harness has two deliberately separate paths:

| Path | Selection | Model calls | Intended use |
| --- | --- | ---: | --- |
| Deterministic | Repository discovery or explicit roots | 0 | CI and autonomous worker verification |
| Model-backed | One file passed to `--model-eval` | 0 on a cache hit, otherwise 1 | Optional, human-authorized judgment of one scenario |

Repository discovery only runs scenarios with an `exec` block. Scenarios that carry only
`expected_behavior` remain useful manual specifications, but discovery never sends them to a model.

## Deterministic checks

```bash
# Discover and run every deterministic scenario, offline:
node tools/evaluate/evaluate.mjs

# Limit deterministic discovery by path or skill name:
node tools/evaluate/evaluate.mjs --filter gh
node tools/evaluate/evaluate.mjs evaluations/audit-skills

# Preview commands. The first line reports zero model calls:
node tools/evaluate/evaluate.mjs --dry-run

# Machine-readable results:
node tools/evaluate/evaluate.mjs --json
```

`--deterministic-only` remains as a compatibility alias. It is unnecessary because deterministic
execution is already the default and the only discovery-backed mode. CI and dispatched workers must
use this path. It is offline and does not probe for the `claude` CLI.

## Optional model evaluation

A human may authorize evaluation of one explicitly named scenario:

```bash
# Preview the exact call count and limits without calling a model:
node tools/evaluate/evaluate.mjs \
  --model-eval evaluations/drafting/onesheet-product.json \
  --dry-run

# Evaluate that one scenario:
node tools/evaluate/evaluate.mjs \
  --model-eval evaluations/drafting/onesheet-product.json
```

The model path cannot accept a directory, discovery filter, or additional roots. Each invocation uses
at most one `claude -p` call with the fixed `claude-haiku-4-5-20251001` model and low effort. Built-in tools and slash
commands are disabled. The child receives a 1,024 output-token limit, is killed after 60 seconds, and
has a 64 KiB output safety limit. Cancellation terminates the full subprocess group.

Before execution, stderr previews the exact model-call count and the hard cap of one. A content-addressed
cache key covers the evaluator contract, model, scenario JSON, prompt, and current `SKILL.md`. Unchanged
inputs reuse the cached verdict and preview zero calls. The default cache is
`$XDG_CACHE_HOME/tron/evaluate` or `~/.cache/tron/evaluate`; `--cache-dir <path>` overrides it.

The retired `--judge` and `--judge-only` flags fail closed with zero model calls. They cannot launch a
discovered batch.

## Scenario format

A deterministic scenario includes an `exec` block:

```json
{
  "skills": ["gh"],
  "query": "Show the gh skill's scripted fast-path commands.",
  "files": [],
  "exec": {
    "cmd": ["bash", "skills/gh/scripts/gh.sh", "help"],
    "expect": {
      "exitCode": 0,
      "stdoutContains": ["gh-view-pr", "gh-list-issues"]
    }
  },
  "expected_behavior": ["Help lists the read-only commands"]
}
```

`exec.cmd` is an argv array run from the repository root. `exec.expect` supports `exitCode`
(default 0), `stdoutContains`, and exact trimmed `stdoutEquals`.

A model or manual scenario omits `exec` and supplies one skill, a query, and observable
`expected_behavior` entries. Only an explicit `--model-eval <file>` may send it to a model.
The optional `sandbox` and `manual` fields remain documentation for interactive/manual runs; the
bounded model path never executes scenario setup or tools.

## Testing the harness

```bash
bash tools/evaluate/test-evaluate.sh
```

The hermetic suite uses a fake `claude` executable. It proves deterministic discovery makes zero calls,
legacy batch flags fail closed, one named scenario makes one bounded call, unchanged inputs hit the
cache, tools are disabled, and cancellation leaves no orphan process. It never calls a real model.
