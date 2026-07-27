# Facilitron voice

Applies to **copy this plugin produces**: article bodies, ticket descriptions, Jira comments, email,
social posts, on-screen video copy, exec reports. Not to the plugin's own instruction files, which
are engineering docs and use em dashes freely.

Link here from a consuming skill instead of restating the rule:

```markdown
Facilitron voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
```

## The rule

No em dashes (`—`) or en dashes (`–`) in produced copy. They read as an AI tell and they make casual
writing feel formal. Scan the draft before publishing rather than trusting you avoided them while
writing:

```bash
grep -n '[—–]' <file>
```

Tone is plain and confident. No hype, no superlatives, no unsupported claims.

## The one exception

`press-release` writes an AP-style dateline (`**<CITY, State> — <Date>** —`), where the em dash is
part of the wire format. Keep it there and nowhere else, so a press release greps clean apart from
its dateline.
