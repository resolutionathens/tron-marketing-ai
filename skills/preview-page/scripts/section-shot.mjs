#!/usr/bin/env node
// Headless Chromium screenshot of a specific section at Figma-native 1440px viewport.
//
// Usage:
//   node section-shot.mjs <url> <section-index> <out-path>   # capture one section
//   node section-shot.mjs <url> list                          # list matched sections, no screenshot
//   node section-shot.mjs <url> full <out-path>               # capture full page
//
// Example:
//   node section-shot.mjs http://localhost:4001/solutions/maintenance-teams 4 /tmp/dev-section4.png
//   node section-shot.mjs http://localhost:4001/solutions/maintenance-teams list
//   node section-shot.mjs http://localhost:4001/solutions/maintenance-teams full /tmp/dev-full.png
//
// section-index selects the Nth element matching the section locator (0-based).
// The locator covers `<main> section`, `<section aria-label>`, and `[class*="py-NN"]`
// for the padding scales we use on heroes (py-14) and feature blocks (py-16/py-20).
// The screenshot is clipped to that section's bounding box, so the output matches
// Figma's section export both in width (1440) and crop bounds.
//
// `list` mode prints a table: idx | aria-label or first heading | section height. Use it
// to pick the right index without eyeballing the page DOM.
//
// `full` mode captures the whole page (fullPage: true) at 1440 wide, for end-of-
// session summary shots and final parity checks against a Figma frame.

import { chromium } from "playwright";

const [, , url, idxArg, outPath] = process.argv;
const listMode = idxArg === "list";
const fullMode = idxArg === "full";

if (!url || !idxArg || (!listMode && !outPath)) {
  console.error(
    "usage: section-shot.mjs <url> <section-index> <out-path>\n" +
      "       section-shot.mjs <url> list\n" +
      "       section-shot.mjs <url> full <out-path>"
  );
  process.exit(2);
}

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: 1440, height: 2400 },
  deviceScaleFactor: 1,
});
const page = await ctx.newPage();

await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });

// Allow Nuxt hydration + any lazy images
await page.waitForLoadState("domcontentloaded");
await page.waitForTimeout(800);

const SELECTOR =
  'main section, section[aria-label], [class*="py-16"], [class*="py-14"], [class*="py-20"]';

if (fullMode) {
  await page.screenshot({ path: outPath, fullPage: true });
  await browser.close();
  console.log(`${outPath} (fullPage at 1440 wide)`);
  process.exit(0);
}

if (listMode) {
  const rows = await page.$$eval(SELECTOR, (els) =>
    els.map((el, i) => {
      const label =
        el.getAttribute("aria-label") ||
        el.querySelector("h1,h2,h3")?.textContent?.trim().slice(0, 60) ||
        "(no label)";
      const rect = el.getBoundingClientRect();
      return { idx: i, label, h: Math.round(rect.height) };
    })
  );
  await browser.close();
  console.log("idx | h(px) | label");
  console.log("----+-------+------------------------------------------------------------");
  for (const r of rows) {
    console.log(`${String(r.idx).padStart(3)} | ${String(r.h).padStart(5)} | ${r.label}`);
  }
  process.exit(0);
}

const idx = parseInt(idxArg, 10);

const target = page.locator(SELECTOR).nth(idx);
await target.waitFor({ state: "visible", timeout: 10000 });
await target.scrollIntoViewIfNeeded();
await page.waitForTimeout(300);

const box = await target.boundingBox();
if (!box) {
  console.error("could not get bounding box for section", idx);
  process.exit(1);
}

await page.screenshot({
  path: outPath,
  clip: { x: 0, y: box.y, width: 1440, height: box.height },
});

await browser.close();
console.log(`${outPath} ${box.width}x${box.height}`);
