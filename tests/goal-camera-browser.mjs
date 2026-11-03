import assert from "node:assert/strict";
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";
import * as G from "../src/game.js";

const browser = await chromium.launch({
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
const presentation = () =>
  page.evaluate(() => window.tabletopFC.getPresentation());
const state = () => page.evaluate(() => window.tabletopFC.getState());
const loaded = () => page.waitForFunction(() => !!window.tabletopFC);

function setup(team, final = false) {
  let s = G.kickoff(G.createGame(), 6, 4);
  const ball = { x: team === "blue" ? 8 : 1, y: team === "blue" ? 3 : 2 };
  Object.assign(s, {
    team,
    opening: false,
    kickoffKind: null,
    phase: "select",
    roll: 1,
    remaining: 1,
    ball,
    half: final ? 2 : 1,
    rolls: final ? { blue: 20, red: 20 } : { blue: 1, red: 1 },
  });
  Object.assign(
    s.pawns.find((p) => p.id === `${team}-4`),
    ball,
  );
  s = G.selectPawn(s, `${team}-4`);
  return s;
}
async function fixture(s, options = {}) {
  await page.evaluate(
    ({ s, options }) => {
      localStorage.setItem(
        "tabletop-fc-match-v2",
        JSON.stringify({
          version: 2,
          state: s,
          baseline: s,
          history: [],
          opponent: "human",
        }),
      );
      localStorage.setItem(
        "tabletop-fc-options",
        JSON.stringify({
          camera: "perspective",
          motion: "system",
          celebrations: true,
          ...options,
        }),
      );
    },
    { s, options },
  );
  await page.reload();
  await loaded();
  await page.locator("#continue-match").click();
  await page.waitForFunction(() => !document.body.dataset.screen);
}
async function cell(x, y) {
  const p = await page.evaluate(
    ({ x, y }) => window.tabletopFC.screenPosition(x, y),
    { x, y },
  );
  await page.mouse.click(p.x, p.y);
}
async function score(team) {
  const y = team === "blue" ? 3 : 2;
  await cell(team === "blue" ? 9 : 0, y);
  await page.waitForFunction(
    (x) => window.tabletopFC.getState().ball.x === x,
    team === "blue" ? 9 : 0,
  );
  await cell(team === "blue" ? 10 : -1, y);
  await page.waitForFunction(() => window.tabletopFC.getState().phase === "goal");
}
async function completed() {
  await page.waitForFunction(
    () => !window.tabletopFC.getPresentation().celebration,
  );
  assert.equal((await presentation()).effects, 0);
  assert.equal((await presentation()).camera, "OrthographicCamera");
  assert.equal(await page.locator("#goal-celebration").isHidden(), true);
  assert.equal(await page.locator("#primary").isEnabled(), true);
}

try {
  await mkdir("test-results", { recursive: true });
  await page.goto(`${process.env.TABLETOP_FC_URL || "http://127.0.0.1:8000"}/?qa`);
  await loaded();
  // Models retain team/keeper identity, and actual moves drive their poses.
  const runner = setup("blue");
  Object.assign(runner, {
    phase: "select",
    selected: null,
    used: [],
    roll: 3,
    remaining: 3,
    free: false,
    ball: { x: 4, y: 3 },
  });
  await fixture(runner);
  const players = await page.evaluate(() => window.tabletopFC.getPlayers());
  assert.equal(players.length, 10);
  assert.equal(players.filter((p) => p.keeper).length, 2);
  assert.equal(new Set(players.map((p) => p.hairstyle)).size, 5);
  assert.ok(players.every((p) => p.model === `footballer-${p.id}`));
  await cell(2, 1);
  await cell(3, 1);
  await page.waitForFunction(
    () =>
      window.tabletopFC.getPlayers().find((p) => p.id === "blue-1").pose ===
      "running",
  );
  await page.waitForFunction(() =>
    window.tabletopFC.getPlayers().every((p) => p.pose === "idle"),
  );
  assert.equal((await state()).pawns.find((p) => p.id === "blue-1").x, 3);
  await fixture(setup("blue"));
  await cell(9, 3);
  await page.waitForFunction(
    () =>
      window.tabletopFC.getPlayers().find((p) => p.id === "blue-4").pose ===
      "kicking",
  );
  assert.equal((await state()).ball.x, 9);
  // Score through real board raycasting. A separate camera must preserve orbit/zoom.
  await fixture(setup("blue"));
  assert.equal((await presentation()).stadium, true);
  await page.mouse.move(720, 500);
  await page.mouse.wheel(0, -80);
  await page.waitForTimeout(300);
  const original = (await presentation()).gameplay;
  assert.notEqual(original.zoom, 1);
  await page.screenshot({ path: "test-results/stadium-play.png" });
  await score("blue");
  const scored = await state();
  assert.equal(scored.score.blue, 1);
  assert.equal((await presentation()).camera, "PerspectiveCamera");
  assert.equal(await page.locator("#primary").isDisabled(), true);
  assert.equal(await page.locator("#goal-team").textContent(), "Blue scores");
  const start = (await presentation()).position;
  await page.waitForFunction(
    () => window.tabletopFC.getPresentation().celebration?.elapsed > 0.9,
  );
  assert.notDeepEqual((await presentation()).position, start);
  assert.ok((await presentation()).effects > 0);
  const celebrating = await page.evaluate(() => window.tabletopFC.getPlayers());
  assert.equal(celebrating.filter((p) => p.pose === "celebrating").length, 5);
  assert.ok(celebrating.every((p) => !p.badge));
  await page.screenshot({ path: "test-results/goal-cinematic.png" });
  await completed();
  await page.waitForFunction(() =>
    window.tabletopFC.getPlayers().every((p) => p.badge && p.pose === "idle"),
  );
  assert.deepEqual(await state(), scored);
  assert.deepEqual((await presentation()).gameplay, original);
  // A saved goal is already celebrated and is immediately ready to continue.
  await page.reload();
  await loaded();
  await page.locator("#continue-match").click();
  await completed();
  assert.deepEqual(await state(), scored);
  await page.locator("#primary").click();
  assert.equal((await state()).phase, "roll");

  // Mirror the shot for Red; keyboard skip restores the top camera and focus.
  await fixture(setup("red"), { camera: "top" });
  const top = (await presentation()).gameplay;
  await score("red");
  assert.equal((await presentation()).celebration.team, "red");
  assert.ok((await presentation()).position[0] < 0);
  assert.equal(await page.locator("#goal-team").textContent(), "Red scores");
  await page.keyboard.press("Enter");
  await completed();
  assert.deepEqual((await presentation()).gameplay, top);
  assert.equal(await page.evaluate(() => document.activeElement.id), "primary");

  // Pausing cancels effects, and a new match cannot receive a stale completion.
  await fixture(setup("blue"));
  await score("blue");
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("body").getAttribute("data-screen"), "pause");
  assert.equal((await presentation()).celebration, null);
  assert.equal((await presentation()).effects, 0);
  await page.locator("#resume-match").click();
  await completed();
  assert.equal((await state()).score.blue, 1);
  await page.locator("#pause-button").click();
  await page.locator("#new-game").click();
  await page.locator("#confirm-restart").click();
  await page.waitForTimeout(4500);
  assert.equal((await state()).phase, "ready");
  assert.deepEqual((await state()).score, { blue: 0, red: 0 });
  assert.equal((await presentation()).camera, "OrthographicCamera");

  // Both the device preference and explicit options bypass motion/effects.
  for (const options of [{ motion: "reduced" }, { celebrations: false }]) {
    await fixture(setup("blue"), options);
    await score("blue");
    await completed();
    assert.equal((await state()).score.blue, 1);
  }
  await page.emulateMedia({ reducedMotion: "reduce" });
  await fixture(setup("red"));
  await score("red");
  await completed();
  await page.emulateMedia({ reducedMotion: "no-preference" });

  // A device preference changed during the shot also cancels it immediately.
  await fixture(setup("blue"));
  await score("blue");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await completed();
  await page.emulateMedia({ reducedMotion: "no-preference" });

  // Resize mid-shot, keep Skip within the phone screen, and finish the match.
  await fixture(setup("red", true));
  await score("red");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(
    () => window.tabletopFC.getPresentation().celebration?.elapsed > 0.9,
  );
  const skip = await page.locator("#skip-goal").boundingBox();
  assert.ok(
    skip.x >= 0 && skip.x + skip.width <= 390 && skip.y + skip.height <= 844,
  );
  await page.screenshot({ path: "test-results/goal-camera-phone.png" });
  await page.locator("#skip-goal").click();
  await completed();
  assert.equal(await page.locator("#primary").textContent(), "Full time");
  await page.screenshot({ path: "test-results/stadium-phone.png" });
  await page.locator("#primary").click();
  assert.equal((await state()).phase, "finished");
  assert.equal((await state()).winner, "red");
  assert.equal(
    await page.locator("body").getAttribute("data-screen"),
    "results",
  );
  assert.deepEqual(errors, []);
  console.log(
    "PASS: footballer identities and running/kicking/cheering poses, live stadium, Blue/Red goal cameras and fireworks, natural completion, keyboard skip, orbit/zoom/top-view restoration, saved goals, pause/restart cancellation, reduced motion changes, effects disabled, phone resize, final-roll goal and no browser errors.",
  );
} finally {
  await browser.close();
}
