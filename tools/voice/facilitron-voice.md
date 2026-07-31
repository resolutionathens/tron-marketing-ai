# Facilitron voice

Applies to **copy this plugin produces**: article bodies, ticket descriptions, Jira comments, email,
social posts, on-screen video copy, exec reports. Not to the plugin's own instruction files, which
are engineering docs and use em dashes freely.

Link here from a consuming skill instead of restating the rule:

```markdown
Facilitron voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
```

This file carries only what a regex cannot check. Skills that write **published marketing copy** also
link `tools/voice/marketing-copy.md`, which carries the brand voice: identity, stance, the proof set,
and the register each format uses. Skills that write internal prose (tickets, comments, reports) need
this file and nothing more, because a Jira comment should not sound like a press release.

## The mechanical layer is Vale, not this file

The banned-word list lives in `skills/prose-lint/styles/Facilitron/*.yml` and is enforced by
`tron:prose-lint`. **Do not restate it here.** Those rules already cover marketing fluff
(`world-class`, `seamless`, `empower`, `unlock`, `elevate`, `delve`, `in today's`, and two dozen
more), wordiness (`leverage` to `use`, `utilize` to `use`, `in order to` to `to`), hedging, house
terminology (`preventive`, never `preventative`), brand capitalization, and link text.

Keeping one banlist in one place is the point: the prose file and the Vale pack disagreed for a
release about whether en dashes were banned, and only the prose file knew (MD-2574). When a new word
needs banning, add a token to the Vale pack. When judgment needs stating, add it here.

## The rule

No em dashes (`—`) or en dashes (`–`) in produced copy. They read as an AI tell and they make casual
writing feel formal. `Facilitron.EmDash` catches both at error level, but scan the draft yourself
before publishing rather than trusting you avoided them while writing:

```bash
grep -n '[—–]' <file>
```

**The one exception** is the AP-style press-release dateline, where the em dash is part of the wire
format. `TokenIgnores` in `vale-ini.template` exempts the bolded dateline run, so a press release
lints clean apart from it. Every other dash in that release is still a finding.

## Universal judgment

Tone is plain and confident. The copy is confident because it is specific, not because it is loud.

- **Specificity beats emphasis.** "24 cents an hour" beats "extremely low rates." If a sentence needs
  an adjective to be interesting, it has no news in it. Adjectives should not do the work numbers
  should be doing.
- **Every number has a source.** Never estimate a figure into existence to make a sentence land, and
  never restate a known figure with different numbers. If it cannot be sourced, cut the sentence
  rather than softening it to "many."
- **Name the limits of a claim.** Volunteering what something is not, or what it does not cover, is
  what authority sounds like here. It is not hedging; hedging is `very`, `basically`, `essentially`,
  and Vale already flags those.
- **One primary CTA**, and it comes last. Secondary links are fine in a newsletter.
- **Lead with the finding or the task**, not with a windup. No rhetorical question standing in for a
  first sentence, and no opening line that would work for any company in any industry.
- **Write for a competent professional short on time.** Explain the process, not the concept. No
  condescension, no "as you may know," no "we've all been there."
- **Straight quotes and apostrophes. Serial comma.** Numerals for figures.

## Verifying

`tron:prose-lint` runs the Vale pack and, for published copy, a voice judgment pass. Run it before
any content skill opens its PR. A clean Vale run means the mechanics are right; it does not mean the
copy sounds like Facilitron, which is what the judgment pass and `marketing-copy.md` are for.
