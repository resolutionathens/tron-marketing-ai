---
name: figma-authoring
model: opus
effort: high
fallback:
  cost: high
  skip_when: "Use tron:figma-authoring only when a dispatch is mutating a Figma file to match a component that already exists in code. To read a Figma design without changing it, use tron:figma-inspect. To export assets, use tron:figma-to-imagekit. To turn a creative ticket into a brief, use tron:creative-request."
  stage_skips:
    - stage: "Extend or build"
      skip_when: "The live read in stage 3 shows no component set at the target node — there is nothing to extend, so build new"
    - stage: "Resolve tokens"
      skip_when: "Every class on the source component is stock Tailwind and the contract does not require bound fills"
description: "Author a Figma component set so it matches the component that already exists in code — the design-system side of a figma-authoring dispatch. Use this skill when a worker must ADD or CHANGE something in a live Figma file: add a variant to an existing component set, rebuild a component set that drifted from the code, bind fills to design-system variables, or add a component text property. Trigger on 'add the orange Badge variant in Figma', 'make the Figma component match the code', 'author this component set', 'bind these fills to the real tokens', or a figma-authoring dispatch naming a file key and node id. Resolves every design token out of the source checkout rather than inferring a hex, extends an existing component set instead of building a parallel one, and verifies variant PROPERTIES rather than appearance. Read-only against source; mutates Figma only through Scout's hash-bound, human-confirmed figma-cli."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Skill
scout:
  surface: false
  effects: [draft]
---

# /figma-authoring — build to the design system, not to a screenshot

You are mutating a live Figma file to match a component that **already exists in code**. The code
is the specification. Your job is to transcribe it exactly — its variant axes, its default, its
text properties, its real tokens — not to design something that looks similar.

Everything here assumes a `figma-authoring` dispatch. Your kickoff already gave you the file key,
the node id, and the **literal path** to Scout's figma-cli. Use that literal path in every command:
`$TRON_FIGMA_CLI` holds it for reference, but a `$VARIABLE`, backtick or `$(…)` in the command is
command substitution and the hook always refuses it.

## What you can and cannot do

The source checkout is **context only**. The hook allows `Read`, `Grep`, `Glob`, `Skill`, the four
figma-cli commands, and this dispatch's own callbacks. `Edit`, `Write`, `git`, and every other
shell command are denied — that is the design, not a misconfiguration. You will not open a PR.

Three figma-cli commands read and need no confirmation. Use them freely:

```bash
bun run <literal figma-cli path> variants <nodeId> --file <fileKey>
bun run <literal figma-cli path> bindings <nodeId> --file <fileKey>
bun run <literal figma-cli path> status
```

One mutates, and every invocation costs a separate human confirmation:

```bash
bun run <literal figma-cli path> apply '<Plugin API JavaScript>' --file <fileKey>
```

`--file` is mandatory on a mutation. The JavaScript is ONE single-quoted argument with **no
apostrophes inside it** — double quotes and backticks are fine — followed by `--file <fileKey>` and
nothing else.

## Workflow

### 1. Read the source component — it is the spec

Find the component in the checkout and extract, verbatim:

- **The prop that becomes the variant axis**, and its **complete** value list, in source order.
- **The default**, from `withDefaults` / a default parameter — not from what looks primary.
- **Every text or slot prop**, which becomes a component **TEXT property** in Figma.
- **The class string for each variant**, which is where the tokens are.

```bash
# example shape — adjust to the repo
rg -n "defineProps|withDefaults|colorMap|cva\(|variants:" app/components/base/
```

Worked example (`marketing-pages`, `app/components/base/Badge.vue`):

| Source | Figma
| --- | ---
| `color?: "red" \| "blue" \| … ` (8 values) | one VARIANT axis `color` with 8 options
| `withDefaults(…, { color: "blue" })` | `defaultVariant: "blue"`
| `text?: string` | a component TEXT property `text`
| `bg-tron-green-800` on `green-solid` | a fill bound to the `tron-green-800` variable

Write the axis name and values down now. They are your contract in stage 5.

### 2. Resolve every token from source — never infer one

**A wrong hex is invisible to every check we have.** This is the failure that produced this skill:
a worker needed `tron-green-800`, guessed `#166534` — stock Tailwind's `green-800` — and shipped a
component that looked right and was wrong. The real value is `#2d8a44`, sitting in a file it could
have grepped.

For each class on the component, resolve it in this order and **record `file:line`**:

1. CSS custom properties — `app/assets/css/tailwind.css` (`--color-tron-green-800: #2d8a44;`)
2. The Tailwind theme — `tailwind.config.ts` (`accent: "#1fb2a6"`)
3. SCSS variables — `app/assets/css/_variables.scss`

```bash
rg -n -- "--color-tron-green-800|tron-green-800" app/assets/css tailwind.config.ts
```

Three rules, and they are absolute:

- **A brand class resolves to a brand token.** `bg-tron-green-800` is a token lookup, always.
- **A stock Tailwind class is stock Tailwind.** `bg-blue-100` is not a brand token; say so in your
  plan rather than quietly promoting it to one.
- **No token, no value.** If the design asks for a color the codebase does not define, you cannot
  invent it — not from the brand palette, not from a sibling ramp, not from a screenshot. Report
  the gap in your plan and stop. A token has to exist in code before it can exist in the component.

### 3. Read the live target before you plan anything

```bash
bun run <literal figma-cli path> variants <nodeId> --file <fileKey>
bun run <literal figma-cli path> bindings <nodeId> --file <fileKey>
```

`variants` reports Figma's own structures: `properties` (the declared schema — VARIANT axes with
their options and default, plus TEXT/BOOLEAN properties) and `variants[].properties` (each child's
axis map). Read both. This tells you what is already there, which decides the next stage. Quote the
relevant part of this output as your plan's `beforeEvidence`.

### 4. Extend the existing set — do not build a parallel one

If the target node is already a component set for this component, **add to it**. Extending
inherits the corner radius, the padding, the text property, and the auto-layout that are already
correct. Building a parallel set beside it reproduces none of that, and the second live run of this
procedure proved it: the rebuilt-from-scratch set had 6px corners instead of the pill radius,
widths from 47 to 110px instead of a uniform 97×28, and no text property at all.

Build new **only** when stage 3 shows no component set at the node. Say which you are doing, and
why, in your plan.

### 5. Write the contract from the source, not from your intent

Submit the plan to `POST <apiBase>/api/dispatches/<id>/figma-authoring-plan` with `target`,
`summary`, `beforeEvidence`, `verificationSteps`, and a `contract`:

```json
{"component":"Badge","axes":{"color":["red","blue","green","green-solid","yellow","orange","gray","violet"]},"defaultVariant":"blue","requireBoundFills":true}
```

The contract is the **end state a human is approving**, and it is checked deterministically after
the mutation — the operation cannot reach `verified` unless the live component matches it. So state
what must actually be true: every axis value from stage 1, the real default, and
`requireBoundFills: true` whenever any variant uses a brand token.

The contract has no field for text properties. That does not make them optional — it makes them
**your** check in stage 7.

### 6. Author the mutation

Full Plugin API recipes: [reference/plugin-api-recipes.md](reference/plugin-api-recipes.md).

Three structural requirements, all of which have been violated by a real run:

- **Variant properties are structural, and Figma derives them from names.** `variantProperties` is
  read-only: you get an axis by naming every child in the set `axis=value` — the *same* axis set on
  *every* child — and Figma builds `componentPropertyDefinitions` from that. Which is exactly why
  this is fragile rather than automatic: a set combined from inconsistently named children makes
  Figma invent positional names, and one real run ended up with `Property 1=Badge, Property 2=blue`
  on six variants that rendered perfectly and were structurally broken. Naming is the input;
  `componentPropertyDefinitions` in stage 7 is the proof.
- **Text is a component TEXT property**, added with `addComponentProperty(…, "TEXT", …)` and bound
  to the text node's `characters`. Baking the variant's label in as static text is the single most
  common failure of this procedure.
- **Fills bind to variables**, via `setBoundVariableForPaint` against the design-system collection.
  A typed-in hex aliases nothing, and `requireBoundFills` will reject it.

Your first `apply` is denied while Scout binds its exact command hash. **Stop.** Wait for the
dashboard to relay human confirmation, then retry that command **unchanged, exactly once**. Every
further `apply` needs its own plan, hash, and fresh confirmation.

### 7. Verify properties, not appearance

```bash
bun run <literal figma-cli path> variants <nodeId> --file <fileKey>
bun run <literal figma-cli path> bindings <nodeId> --file <fileKey>
```

Scout records both automatically and checks them against your contract. Before you call it done,
read them yourself and confirm:

- `properties` declares the axis with **exactly** the values from stage 1, and the right `default`.
- Every child in `variants[]` has a non-null `properties` map. A `null` there is the mangled-set
  signature.
- `properties` contains the **TEXT** entry from stage 1 — the contract will not catch its absence.
- `bindings` names real design-system variables, and the one bound to your brand class resolves to
  the hex you recorded in stage 2.

Never self-report verification prose. The reads are the evidence.

## The four failures this skill exists to prevent

Measured on the first live run, against the Badge it was meant to match:

1. No `text` component property — each variant's label baked in as static text.
2. 6px corner radius instead of the pill radius, because the set was rebuilt rather than extended.
3. Variant widths from 47 to 110px instead of a uniform 97×28 — same cause.
4. Fills typed in as hex against a bespoke collection, aliasing nothing in the design system, with
   `tron-green-800` guessed as stock Tailwind's `#166534` instead of the real `#2d8a44`.

Every one of them renders convincingly. None of them survives stage 7.
