# Facilitron voice — the shared rule

The single source for the voice rules that apply to **copy this plugin produces**: article bodies,
ticket descriptions, Jira comments, email, social posts, on-screen video copy, exec reports.

It does not govern the plugin's own instruction files. `SKILL.md` bodies, `reference/*.md`, and
`CLAUDE.md` are engineering docs written for an agent, not Facilitron-voice copy, and they use em
dashes freely.

Link to this file from a consuming skill instead of restating the rule:

```markdown
Facilitron voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
```

## No em dashes

Never use `—` (em dash) or `–` (en dash) in produced copy.

Two reasons, and the second is the one people forget. It is a well-known AI tell, so it undercuts
the credibility of anything published under a human byline. It also makes casual writing feel
formal: a Jira comment or a social post reads stiffer with an em dash in it than the same sentence
punctuated any other way.

This is one of the easier rules to slip on mid-draft. Scan the draft for the character before
publishing rather than trusting that you avoided it while writing.

### What to use instead

Pick whichever keeps the sentence natural:

| Instead of an em dash    | Use                                                        |
| ------------------------ | ---------------------------------------------------------- |
| A hard break in thought  | A period. Split it into two sentences.                     |
| An aside                 | Commas, or parentheses.                                     |
| A consequence or pivot   | A conjunction: `and`, `but`, `so`.                          |
| A label before a clause  | A colon.                                                    |

Do not swap in a spaced hyphen (` - `) as a lookalike. If none of the above fits, the sentence
wants rewriting, not repunctuating.

### The one exception: AP datelines

`press-release` writes an AP-style dateline, where the em dash is part of the wire format rather
than prose:

```
**<CITY, State> — <Date>** —
```

Keep it there. The exception covers the dateline only; the body of the release follows the rule
like everything else.

## Tone

Plain and confident. No hype, no marketing superlatives, no unsupported claims. Write like a
knowledgeable colleague explaining something, not like a brochure.

## Verifying

Grep the produced file before publishing. Both dash characters, since the en dash is the common
near-miss:

```bash
grep -n '[—–]' <file>
```

For a press release, expect exactly the dateline hits and nothing else.
