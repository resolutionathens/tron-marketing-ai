#!/usr/bin/env node
// Headless Chromium screenshot of a page at an arbitrary viewport width.
//
// Exists because the cmux browser pane (macOS WKWebView) can't resize below
// the pane width, so mobile / responsive / CLS work can't be self-verified
// there. This reuses the same Playwright/Chromium dep as section-shot.mjs.
//
// Usage:
//   node responsive-shot.mjs <url> <width|preset> <out-path> [--full]
//
// Presets:  mobile = 375 (dsf 2)   tablet = 768 (dsf 2)   desktop = 1440 (dsf 1)
// A raw number works too; deviceScaleFactor defaults to 2 at <=768px, else 1.
//
// By default captures the above-the-fold viewport (what matters for hero / LCP
// / CLS). Pass --full for a full-page capture.
//
// Examples:
//   node responsive-shot.mjs http://localhost:4001/ mobile /tmp/home-375.png
//   node responsive-shot.mjs http://localhost:4001/ 414 /tmp/home-414.png --full
//   node responsive-shot.mjs http://localhost:4001/facility-owners/guide-to-facilities-management mobile /tmp/guide-375.png --full

import { chromium } from "playwright";

const args = process.argv.slice(2);
const full = args.includes("--full");
const [url, sizeArg, outPath] = args.filter((a) => a !== "--full");

if (!url || !sizeArg || !outPath) {
  console.error(
    "usage: responsive-shot.mjs <url> <width|preset> <out-path> [--full]\n" +
      "       presets: mobile (375), tablet (768), desktop (1440)"
  );
  process.exit(2);
}

const PRESETS = {
  mobile: { width: 375, height: 812, dsf: 2 },
  tablet: { width: 768, height: 1024, dsf: 2 },
  desktop: { width: 1440, height: 900, dsf: 1 },
};

let viewport;
if (PRESETS[sizeArg]) {
  const p = PRESETS[sizeArg];
  viewport = { width: p.width, height: p.height, dsf: p.dsf };
} else {
  const width = parseInt(sizeArg, 10);
  if (!Number.isFinite(width) || width < 200) {
    console.error(`invalid width/preset: ${sizeArg}`);
    process.exit(2);
  }
  viewport = { width, height: width <= 768 ? 812 : 900, dsf: width <= 768 ? 2 : 1 };
}

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: viewport.width, height: viewport.height },
  deviceScaleFactor: viewport.dsf,
  isMobile: viewport.width <= 768,
});
const page = await ctx.newPage();

await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
await page.waitForLoadState("domcontentloaded");
// Let Nuxt hydrate and lazy/eager images settle (matters for CLS inspection).
await page.waitForTimeout(800);

await page.screenshot({ path: outPath, fullPage: full });
await browser.close();

console.log(
  `${outPath} ${viewport.width}x${viewport.height}@${viewport.dsf}x ${full ? "(full page)" : "(fold)"}`
);
