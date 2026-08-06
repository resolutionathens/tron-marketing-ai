# Plugin API recipes for `figma-cli apply`

Every snippet here is written for **one single-quoted `apply` argument** — so: no apostrophes
anywhere, double quotes only. Return a small JSON-able object at the end; the CLI prints it and the
hook records it.

## Contents

- [The shape of an `apply` argument](#the-shape-of-an-apply-argument)
- [Resolve nodes, and fail loudly](#resolve-nodes-and-fail-loudly)
- [Add a variant to an existing component set](#add-a-variant-to-an-existing-component-set)
- [Bind a fill to a design-system variable](#bind-a-fill-to-a-design-system-variable)
- [Create a variable only when the token exists in code](#create-a-variable-only-when-the-token-exists-in-code)
- [Build a component set from scratch](#build-a-component-set-from-scratch)
- [Add a component TEXT property](#add-a-component-text-property)
- [Things that will cost you a confirmation](#things-that-will-cost-you-a-confirmation)

## The shape of an `apply` argument

```bash
bun run <literal figma-cli path> apply 'const set = await figma.getNodeByIdAsync("3:203"); … return { ok: true };' --file WfRPllD04ORdJ074hu4iFP
```

The body runs as an async function, so `await` at the top level is fine and `return` is how you
report. Node ids are strings and always quoted. `--file` is mandatory — without it the command
lands on whichever document Figma Desktop has in front, which may not be the one anyone reviewed.

## Resolve nodes, and fail loudly

Resolve everything you touch up front and return an error object rather than letting an exception
escape. A clean error costs you a confirmation; a stack trace costs you the same confirmation and
tells the human less.

```js
const set = await figma.getNodeByIdAsync("3:203");
if (!set) return { error: "component set 3:203 not found" };
const source = await figma.getNodeByIdAsync("1:27");
if (!source) return { error: "source variant 1:27 not found" };
```

## Add a variant to an existing component set

The preferred path — see the skill's "extend, do not build a parallel one". Cloning an existing
variant inherits its radius, padding, auto-layout, text property, and size for free.

```js
const clone = source.clone();
clone.name = "color=teal";        // axis=value, matching every sibling exactly
set.appendChild(clone);
```

`clone.name` is the whole mechanism. `variantProperties` is read-only; Figma derives the axis map
from these names. If siblings are named `color=blue`, your child must be `color=teal` — not
`Teal`, not `Badge/teal`, not `color = teal`. A multi-axis set uses
`size=lg, color=teal` with the same axes in the same order as its siblings.

## Bind a fill to a design-system variable

`setBoundVariableForPaint` **returns a new paint** — it does not mutate in place, and `fills` is
read-only, so you must reassign the whole array.

```js
const bound = clone.fills.map((paint) =>
  paint.type === "SOLID" ? figma.variables.setBoundVariableForPaint(paint, "color", variable) : paint
);
clone.fills = bound;
```

To find the variable a sibling already uses — the reliable way to land in the *same* collection
rather than a bespoke one:

```js
const fill = source.fills.find((f) => f.type === "SOLID");
if (!fill || !fill.boundVariables || !fill.boundVariables.color) {
  return { error: "source variant fill has no bound color variable to mirror" };
}
const sourceVar = await figma.variables.getVariableByIdAsync(fill.boundVariables.color.id);
const collection = await figma.variables.getVariableCollectionByIdAsync(sourceVar.variableCollectionId);
```

## Create a variable only when the token exists in code

Reuse before you create. Only create when the token is real in source and Figma simply lacks it —
never to give a made-up color a home.

```js
const all = await figma.variables.getLocalVariablesAsync("COLOR");
let variable = all.find((v) => v.variableCollectionId === collection.id && v.name === "accent/accent");
if (!variable) {
  variable = figma.variables.createVariable("accent/accent", collection, "COLOR");
  for (const mode of collection.modes) {
    // #1fb2a6 — tailwind.config.ts:154. Convert from the hex you RESOLVED, never one you recalled.
    variable.setValueForMode(mode.modeId, { r: 31 / 255, g: 178 / 255, b: 166 / 255, a: 1 });
  }
}
```

Figma wants 0–1 floats, so write the division out (`31 / 255`) rather than pre-computing it — the
literal hex stays visible in the command the human reviews.

## Build a component set from scratch

Only when stage 3 showed no component set at the node.

```js
const made = values.map((value) => {
  const component = figma.createComponent();
  component.name = "color=" + value;   // identical axis on every child, or Figma invents "Property 1"
  return component;
});
const set = figma.combineAsVariants(made, figma.currentPage);
set.name = "Badge";
```

`combineAsVariants` is where a naming inconsistency becomes a mangled set. Every component in the
array must carry the same axis names in the same order before you combine, and stage 7's `variants`
read is the only thing that proves it did.

## Add a component TEXT property

A text property lives on the set and binds to the text node's `characters`. Bake the label in as
static text and the component is wrong no matter how it renders.

```js
const property = set.addComponentProperty("text", "TEXT", "Badge");
for (const child of set.children) {
  const label = child.findOne((n) => n.type === "TEXT");
  if (label) label.componentPropertyReferences = { characters: property };
}
```

`addComponentProperty` returns the property's *full* id (`text#12:3`) — that suffixed id is what
`componentPropertyReferences` needs, so use the return value rather than retyping the name.

## Things that will cost you a confirmation

Each of these fails the whole `apply`, and a retry is a new plan, a new hash, and a new human:

- An apostrophe anywhere in the argument (`don't`, `it's`, a possessive in a string) — it closes the
  single-quoted argument early.
- `figma.getNodeById` instead of `getNodeByIdAsync`; the sync form is unavailable.
- Assigning into `fills[0]` instead of reassigning the whole `fills` array.
- Missing `--file`, or anything after `--file <fileKey>`.
- `;` `&` `|` `<` `>` backtick or `$` outside the single-quoted span — the hook refuses chaining,
  pipes, redirection, substitution, and heredocs.
