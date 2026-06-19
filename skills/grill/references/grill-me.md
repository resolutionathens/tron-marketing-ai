# Grill-Me Framework

The questioning discipline `/grill` runs against marketing content — articles, guides, SOPs, landing copy,
briefs, emails. It finds weakness in the *substance* of a piece before a reviewer or customer does. It is not
a style or link check (that's `/vale-prose-lint` and `/lychee-link-check`) — it interrogates the argument.

## The Four Dimensions

### 1. Assumption Audit
Find claims stated as fact that haven't been validated.

**Probes:**
- "How do we know {claim} is true?"
- "What's the source — a customer, a stat, a Search Console query, or a guess we're treating as a finding?"
- "If a reader disagreed with {assumption}, what in this piece would change their mind?"

**Common offenders:**
- Audience claims ("facilities directors struggle with X") with no customer quote, support ticket, or data behind them
- "Studies show" / "research proves" with no citation or link
- "Industry standard" / "best practice" / "everyone knows" as a load-bearing premise
- A statistic with no source, or a source that doesn't say what the sentence claims
- SEO intent assumed ("people search for this") with no keyword evidence

### 2. Specificity Check
Find vague language pretending to be precise. This is where marketing copy is weakest.

**Probes:**
- "What does {fuzzy phrase} look like in a number, a step, or a before/after?"
- "Replace {abstract benefit} with the concrete thing the reader can now do."
- "If I cut this sentence, does the piece lose information or just lose air?"

**Common offenders:**
- Puffery — "streamline," "powerful," "seamless," "robust," "intuitive," "game-changing," "next-generation"
- Benefits with no proof — "save time" (how much?), "easier" (than what?), "faster" (baseline?)
- A headline that promises a specific payoff the body never delivers
- A CTA that's vague ("learn more") where a concrete next action would convert better
- Hand-wavy mechanism — "our platform handles it" without saying how

### 3. Edge Case Sweep
Find the angles, objections, and audiences the piece ignores.

| Surface | What to Probe |
|---|---|
| Audience fit | Who is this NOT for? Does a claim break for part of the stated audience (small district vs. large, K-12 vs. parks & rec vs. higher ed)? |
| Objections | What's the obvious "yeah, but…" a skeptical reader has — and does the piece answer it? |
| Proof gaps | Every claim that would make a reader go "prove it" — is the proof there? |
| Funnel stage | Does the piece match where the reader is (top-of-funnel awareness vs. bottom-of-funnel evaluation)? A how-to and a sales page fail differently. |
| How-to completeness | For instructional content: empty/edge states, "what if it doesn't work," prerequisites, the step everyone forgets |
| Accuracy & risk | Any claim that's legally or factually risky — pricing, guarantees, competitor comparisons, compliance/accessibility statements |
| Dead ends | Where does the reader go next? Is the internal link / CTA present and pointed at the right page? |

### 4. Reviewer Lens
Anticipate the pushback from each person who will see this before (or after) it ships.

| Reviewer | Common Pushback |
|---|---|
| SEO | "What's the target keyword, and is it in the title, H1, and first paragraph?" "Does this match search intent?" "Are the internal links pointed at the canonical pages?" |
| Brand / voice | "Is this our voice, or generic content-mill copy?" "Does the tone match the audience?" "Are we overclaiming?" |
| Legal / compliance | "Can we substantiate this claim?" "Is this accessibility/pricing/guarantee statement accurate?" "Are competitor mentions fair and factual?" |
| Target persona (the reader) | "How does this help me do my job today?" "Why should I trust this?" "What do I do next?" |
| Subject-matter expert | "Is this technically correct?" "Would a practitioner roll their eyes at any of this?" |

## Per-Artifact Checklists

### News / cluster article
- [ ] Title and H1 carry the primary keyword; intent matches what a searcher wants
- [ ] Opening earns the read — no throat-clearing before the value
- [ ] Every factual claim has a source or is self-evidently true
- [ ] Statistics are cited and the source supports the sentence
- [ ] Headings are scannable and promise what their section delivers
- [ ] Internal links point at canonical pages (watch the known traps — e.g. `/product/facilitron-scheduling-and-reservations`, not the indexless `/product/scheduling-and-reservations/`)
- [ ] Has a clear next step / CTA, not a dead end
- [ ] No puffery doing the work that a proof point should
- [ ] Image alt text is a real description (WCAG mandate on the marketing site)

### Guide
- [ ] Audience and outcome are stated up front ("by the end you'll be able to…")
- [ ] Prerequisites / "what you'll need" present
- [ ] Steps are in the right order with nothing assumed-but-unstated
- [ ] Troubleshooting / "if it doesn't work" covered
- [ ] Examples are concrete, not abstract

### Toolkit item (SOP / checklist / template)
- [ ] Imperative voice on every step
- [ ] Each step is a single, checkable action
- [ ] No step depends on context the reader doesn't have yet
- [ ] Edge / failure cases noted where they matter

### Landing-page / product-page copy
- [ ] Hero answers "what is this and who is it for" in one read
- [ ] Every benefit ties to a concrete capability or proof point
- [ ] One primary CTA, unambiguous
- [ ] Claims are substantiable (especially comparisons and guarantees)
- [ ] Matches funnel stage — evaluation copy, not blog copy

### Campaign / messaging brief
- [ ] Audience is specific (a named persona/segment, not "customers")
- [ ] The single core message is identifiable in one sentence
- [ ] Proof points are real and ranked (named customer > metric > industry stat > internal estimate)
- [ ] Channel fit is considered (the same message lands differently in email vs. social vs. in-app)
- [ ] Success is defined (what does this campaign move?)

### Email / social post
- [ ] Subject / first line earns the open (and is honest about the body)
- [ ] One ask, one CTA
- [ ] No internal jargon leaking to a customer audience
- [ ] Length matches the channel

### Ideation Note (from /brainstorm)
- [ ] Audience is specific (not "customers")
- [ ] The hypothesis is falsifiable — signal could prove it wrong
- [ ] The discovery work listed is concrete (not "do more research")

## Calibration

Match the grill to the artifact's stage:

| Stage | Calibration |
|---|---|
| Rough draft | Hard grill — surface everything |
| Pre-review | Hard on Blockers, soft on Polish |
| Pre-publish | Hard on accuracy, claims, audience fit, and SEO |
| Already live | Light grill — focus on improvements worth a revision, not nitpicking |

## Anti-patterns to Avoid

- ❌ Critique without a fix recommendation — "this is weak" with no path forward
- ❌ Flag every micro-imperfection — calibrate to severity
- ❌ Re-do the mechanical gates — style nits belong to `/vale-prose-lint`, broken links to `/lychee-link-check`
- ❌ Grill content that already shipped as if it were a draft — focus on what's worth revising
- ❌ Invent an audience the brief never named — grill the piece in front of you, not an imagined one
