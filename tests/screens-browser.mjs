import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdir } from "node:fs/promises";
import * as G from "../src/game.js";
const { chromium } = createRequire(import.meta.url)("playwright");
const base = process.env.TABLETOP_FC_URL || "http://127.0.0.1:8000";
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  headless: true,
  args: [
    "--no-sandbox",
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
  ],
});
const page = await browser.newPage({
  viewport: { width: 1440, height: 1000 },
  reducedMotion: "no-preference",
});
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
const state = () => page.evaluate(() => window.tabletopFC.getState());
const loaded = () => page.waitForFunction(() => !!window.tabletopFC);
async function screen(name) {
  assert.equal(await page.locator("body").getAttribute("data-screen"), name);
  assert.equal(
    await page.locator("#game-screens").evaluate((el) => el.open),
    true,
  );
}
async function fixture(s, opponent = "human", enter = true) {
  await page.evaluate(
    ({ s, opponent }) =>
      localStorage.setItem(
        "tabletop-fc-match-v2",
        JSON.stringify({
          version: 2,
          state: s,
          baseline: s,
          history: [],
          opponent,
        }),
      ),
    { s, opponent },
  );
  await page.reload();
  await loaded();
  await screen("home");
  if (enter) await page.locator("#continue-match").click();
}
async function options() {
  await page
    .locator('[data-panel]:not([hidden]) [data-open-screen="options"]')
    .click();
  await screen("options");
}
function finalTurn(blue, red) {
  const s = G.kickoff(G.createGame(), 6, 4);
  Object.assign(s, {
    phase: "review",
    team: "blue",
    opening: false,
    kickoffKind: null,
    half: 2,
    rolls: { blue: 20, red: 20 },
    score: { blue, red },
    remaining: 0,
    ball: { x: 6, y: 3 },
  });
  return s;
}
try {
  await mkdir("test-results", { recursive: true });
  await page.goto(`${base}/?qa`);
  await loaded();
  await screen("home");
  assert.equal(await page.locator("#continue-match").isHidden(), true);
  for (const selector of [
    "#start-ai",
    "#start-local",
    '[data-panel="home"] [data-open-screen="options"]',
    '[data-open-screen="credits"]',
  ])
    assert.equal(await page.locator(selector).isVisible(), true);
  await page.screenshot({ path: "test-results/title-screen.png" });
  // Settings are available before starting, saved, and reflected in play.
  await options();
  await page.locator("#option-camera").selectOption("top");
  await page.locator("#option-directions").selectOption("hide");
  await page.locator("#option-motion").selectOption("reduced");
  assert.equal(
    await page
      .locator("html")
      .evaluate((el) => el.classList.contains("reduced-motion")),
    true,
  );
  await page.keyboard.press("Escape");
  await screen("home");
  await page.locator('[data-open-screen="credits"]').click();
  await screen("credits");
  assert.match(
    await page.locator('[data-panel="credits"]').textContent(),
    /Three.js/,
  );
  await page.keyboard.press("Escape");
  await screen("home");
  await page.keyboard.press("ArrowDown");
  assert.equal(
    await page.evaluate(() => document.activeElement.id),
    "start-local",
  );
  await page.keyboard.press("ArrowUp");
  assert.equal(
    await page.evaluate(() => document.activeElement.id),
    "start-ai",
  );
  for (let i = 0; i < 9; i++) {
    await page.keyboard.press("Tab");
    assert.equal(
      await page.evaluate(() =>
        document
          .getElementById("game-screens")
          .contains(document.activeElement),
      ),
      true,
    );
  }
  await page.reload();
  await loaded();
  await options();
  assert.equal(await page.locator("#option-camera").inputValue(), "top");
  assert.equal(await page.locator("#option-motion").inputValue(), "reduced");
  assert.equal(await page.locator("#option-directions").inputValue(), "hide");
  await page.locator("#option-motion").selectOption("system");
  await page.keyboard.press("Escape");
  await page.locator("#start-ai").click();
  assert.equal(
    await page.locator("#game-screens").evaluate((el) => el.open),
    false,
  );
  assert.equal(await page.locator("#opponent").inputValue(), "computer");
  assert.equal(
    await page.locator("#top-view").getAttribute("aria-pressed"),
    "true",
  );
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  const playCamera = await page.evaluate(() =>
    [
      [0, 0],
      [9, 5],
    ].map(([x, y]) => window.tabletopFC.screenPosition(x, y)),
  );
  // Pause/back navigation and replacement confirmation preserve the current match.
  await page.keyboard.press("Escape");
  await screen("pause");
  const saved = await state();
  await options();
  await page.keyboard.press("Escape");
  await screen("pause");
  await page.locator("#new-game").click();
  await page.getByRole("button", { name: "Keep current match" }).click();
  assert.deepEqual(await state(), saved);
  await screen("pause");
  await page.locator("#resume-match").click();
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  const resumedCamera = await page.evaluate(() =>
    [
      [0, 0],
      [9, 5],
    ].map(([x, y]) => window.tabletopFC.screenPosition(x, y)),
  );
  for (let i = 0; i < 2; i++) {
    assert.ok(Math.abs(playCamera[i].x - resumedCamera[i].x) < 1);
    assert.ok(Math.abs(playCamera[i].y - resumedCamera[i].y) < 1);
  }
  await page.locator("#pause-button").click();
  await page.locator("#pause-main-menu").click();
  await screen("home");
  assert.equal(await page.locator("#continue-match").isVisible(), true);
  await page.locator("#start-local").click();
  assert.equal(
    await page.locator("#restart-dialog").evaluate((el) => el.open),
    true,
  );
  await page.locator("#confirm-restart").click();
  assert.equal(await page.locator("#opponent").inputValue(), "human");
  assert.deepEqual((await state()).score, { blue: 0, red: 0 });
  // No computer moves on the title or pause screens, including a saved CPU turn.
  const kickoff = G.kickoff(G.createGame(), 1, 6);
  await fixture(kickoff, "computer", false);
  await page.waitForTimeout(800);
  assert.deepEqual(await state(), kickoff);
  await page.locator("#continue-match").click();
  await page.locator("#pause-button").click();
  await screen("pause");
  const paused = await state();
  await page.waitForTimeout(800);
  assert.deepEqual(await state(), paused);
  await page.locator("#pause-main-menu").click();
  await page.locator("#continue-match").click();
  await page.waitForFunction(
    () =>
      window.tabletopFC.getState().team === "blue" &&
      window.tabletopFC.getState().phase === "roll",
  );
  assert.deepEqual((await state()).rolls, { blue: 0, red: 0 });
  // Wins, losses, draws and local winners each get the correct screen.
  for (const [mode, blue, red, title, celebrate] of [
    ["computer", 3, 1, "You win!", true],
    ["computer", 1, 3, "Red wins!", false],
    ["human", 1, 3, "Red wins!", true],
    ["human", 4, 2, "Blue wins!", true],
    ["human", 2, 2, "It's a draw!", false],
  ]) {
    await fixture(finalTurn(blue, red), mode);
    await page.locator("#primary").click();
    await screen("results");
    assert.equal(await page.locator("#results-title").textContent(), title);
    assert.equal(
      await page.locator("#results-blue").textContent(),
      String(blue),
    );
    assert.equal(await page.locator("#results-red").textContent(), String(red));
    assert.equal(await page.locator("#results-trophy").isVisible(), celebrate);
    assert.equal((await page.locator("#confetti i").count()) > 0, celebrate);
    if (mode === "computer" && blue === 3) {
      await page.waitForTimeout(900);
      await page.screenshot({ path: "test-results/victory-screen.png" });
    }
    if (blue === red)
      await page.screenshot({ path: "test-results/draw-screen.png" });
    await page.keyboard.press("Escape");
    await screen("results");
    await page.locator("#play-again").click();
    assert.equal((await state()).phase, "ready");
    assert.deepEqual((await state()).rolls, { blue: 0, red: 0 });
    assert.deepEqual((await state()).score, { blue: 0, red: 0 });
    assert.equal(await page.locator("#opponent").inputValue(), mode);
    assert.equal(
      await page.locator("#top-view").getAttribute("aria-pressed"),
      "true",
    );
  }
  // A normal goal isn't a match victory; a final-roll goal is.
  let goal = finalTurn(3, 1);
  goal.phase = "goal";
  goal.half = 1;
  goal.rolls = { blue: 1, red: 0 };
  await fixture(goal, "computer");
  assert.equal(
    await page.locator("#game-screens").evaluate((el) => el.open),
    false,
  );
  goal = finalTurn(3, 1);
  goal.phase = "goal";
  await fixture(goal, "computer");
  await page.locator("#primary").click();
  await screen("results");
  // Results survive reload; Main menu offers them again without starting a new match.
  await page.locator("#results-main-menu").click();
  await screen("home");
  assert.equal(
    await page.locator("#continue-label").textContent(),
    "View match result",
  );
  await page.reload();
  await loaded();
  await page.locator("#continue-match").click();
  await screen("results");
  assert.equal(await page.locator("#results-title").textContent(), "You win!");
  // Reduced motion and the celebration toggle work independently.
  await page.locator("#results-main-menu").click();
  await options();
  await page.locator("#option-motion").selectOption("reduced");
  await page.keyboard.press("Escape");
  await page.locator("#continue-match").click();
  assert.equal(await page.locator("#confetti i").count(), 0);
  assert.equal(
    await page
      .locator("#results-trophy")
      .evaluate((el) => getComputedStyle(el).animationName),
    "none",
  );
  await page.locator("#results-main-menu").click();
  await options();
  await page.locator("#option-motion").selectOption("system");
  await page.locator("#option-celebrations").uncheck();
  await page.keyboard.press("Escape");
  await page.locator("#continue-match").click();
  assert.equal(await page.locator("#confetti i").count(), 0);
  // Menus scroll within the screen on phones and short landscape windows.
  for (const viewport of [
    { width: 390, height: 844 },
    { width: 320, height: 568 },
    { width: 844, height: 390 },
  ]) {
    await page.setViewportSize(viewport);
    await page.screenshot({
      path: `test-results/results-${viewport.width}.png`,
    });
    await page.locator("#results-main-menu").click();
    await screen("home");
    assert.ok(
      await page
        .locator("#game-screens")
        .evaluate((el) => el.scrollWidth <= el.clientWidth + 1),
    );
    await page.screenshot({ path: `test-results/title-${viewport.width}.png` });
    await options();
    await page.locator("#option-celebrations").check();
    await page.screenshot({
      path: `test-results/options-${viewport.width}.png`,
    });
    await page.locator('[data-panel="options"] .screen-back').click();
    await page.locator("#continue-match").click();
    await screen("results");
    assert.ok(
      await page
        .locator("#game-screens")
        .evaluate((el) => el.scrollWidth <= el.clientWidth + 1),
    );
  }
  assert.deepEqual(errors, []);
  console.log(
    "PASS: title/mode selection, saved-game continue, replacement confirmation, pause/AI cancellation, options persistence, credits, keyboard focus/back navigation, solo win/loss, local winners, draw, final-goal result, celebrations and reduced motion, rematch, result reload, phone/landscape layouts, no browser errors.",
  );
} catch (error) {
  console.error(error);
  await page
    .screenshot({ path: "test-results/screens-failure.png" })
    .catch(() => {});
  console.error(
    "Screen:",
    await page
      .locator("body")
      .getAttribute("data-screen")
      .catch(() => "browser closed"),
  );
  throw error;
} finally {
  await browser.close();
}
