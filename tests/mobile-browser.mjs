import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";
import * as G from "../src/game.js";

const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  headless: true,
});
const page = await browser.newPage({
  isMobile: true,
  hasTouch: true,
  reducedMotion: "reduce",
});
const errors = [];
page.on("pageerror", (error) => errors.push(error.message));
const base = process.env.TABLETOP_FC_URL || "http://127.0.0.1:8000";

async function checkControls() {
  await page.evaluate(() => new Promise((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(resolve)),
  ));
  const problems = await page.evaluate(() => {
    const issues = [];
    for (const el of document.querySelectorAll(
      ".hud-header button, .turn-dock button, #turn-menu-button",
    )) {
      const r = el.getBoundingClientRect();
      if (!el.checkVisibility()) continue;
      if (r.width < 44 || r.height < 44) issues.push(`${el.id || el.ariaLabel}: small target`);
      if (r.left < 0 || r.top < 0 || r.right > innerWidth + 1 || r.bottom > innerHeight + 1)
        issues.push(`${el.id || el.ariaLabel}: off screen`);
    }
    for (const [x, y] of [[0, 0], [9, 0], [0, 5], [9, 5], [-1, 2], [10, 3]]) {
      const p = window.tabletopFC.screenPosition(x, y);
      if (document.elementFromPoint(p.x, p.y)?.tagName !== "CANVAS")
        issues.push(`Pitch ${x},${y} covered`);
    }
    return issues;
  });
  assert.deepEqual(problems, [], JSON.stringify(page.viewportSize()));
  assert.equal(await page.locator("#direction-pad").isHidden(), true);
  assert.equal(await page.locator("#pawn-picker").count(), 0);
  const dock = await page.locator("#turn-dock").boundingBox();
  assert.ok(dock.height <= 112, `Compact dock is ${dock.height}px tall`);
}

async function tapCell(x, y) {
  const point = await page.evaluate(([x, y]) => window.tabletopFC.screenPosition(x, y), [x, y]);
  await page.touchscreen.tap(point.x, point.y);
}

try {
  await mkdir("test-results", { recursive: true });
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 390, height: 844 },
    { width: 568, height: 320 },
    { width: 844, height: 390 },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto(`${base}/?qa`);
    await page.waitForFunction(() => !!window.tabletopFC);
    const state = G.kickoff(G.createGame(), 6, 4);
    Object.assign(state, {
      phase: "roll", opening: false, kickoffKind: null,
      ball: { x: 3, y: 1 }, selected: null, used: [], remaining: 0, roll: 0,
    });
    const selected = G.rollDie(state, 6);
    await page.evaluate((state) => localStorage.setItem("tabletop-fc-match-v2",
      JSON.stringify({ version: 2, state, baseline: state, history: [], opponent: "human" }),
    ), selected);
    await page.reload();
    await page.waitForFunction(() => !!window.tabletopFC);
    assert.ok(await page.locator("#game-screens").evaluate((el) => el.scrollWidth <= el.clientWidth));
    await page.locator('[data-panel="home"] [data-open-screen="options"]').tap();
    await page.locator("#option-directions").selectOption("auto");
    await page.locator("#option-camera").selectOption("perspective");
    await page.locator('[data-panel="options"] .screen-back').tap();
    await page.locator("#continue-match").tap();
    await checkControls();
    await tapCell(2, 1);
    assert.equal((await page.evaluate(() => window.tabletopFC.getState())).selected, "blue-1");
    await checkControls();
    await page.screenshot({ path: `test-results/touch-${viewport.width}.png` });
    await tapCell(3, 1);
    assert.equal((await page.evaluate(() => window.tabletopFC.getState())).remaining, 5);
    assert.equal((await page.evaluate(() => window.tabletopFC.getState())).phase, "kick");
    await checkControls();
    await tapCell(4, 1);
    assert.deepEqual((await page.evaluate(() => window.tabletopFC.getState())).ball, { x: 4, y: 1 });
    await checkControls();
    await page.locator("#turn-menu-button").tap();
    await page.locator("#top-view").tap();
    await checkControls();
    await page.locator("#pause-button").tap();
    await page.locator("#resume-match").tap();
    await checkControls();
    await page.setViewportSize({ width: viewport.height, height: viewport.width });
    await checkControls();
  }
  assert.deepEqual(errors, []);
  console.log("PASS: compact action bar, direct player/move/kick taps, camera menu, rotation, pause/resume, and unobscured pitch on portrait and landscape phones.");
} finally {
  await browser.close();
}
