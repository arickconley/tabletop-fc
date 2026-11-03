import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdir } from "node:fs/promises";
import * as G from "../src/game.js";
const { chromium } = createRequire(import.meta.url)("playwright");
const base = process.env.GRIDKICK_URL || "http://127.0.0.1:8000";
const browser = await chromium.launch({
  headless: true,
  args: [
    "--no-sandbox",
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
  ],
});
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
const state = () => page.evaluate(() => window.gridkick.getState());
async function loaded() {
  await page.waitForFunction(() => !!window.gridkick);
}
async function fixture(s, opponent = "computer", baseline = s) {
  await page.evaluate(
    ({ s, opponent, baseline }) =>
      localStorage.setItem(
        "gridkick60-match-v2",
        JSON.stringify({
          version: 2,
          state: s,
          baseline,
          history: [],
          opponent,
        }),
      ),
    { s, opponent, baseline },
  );
  await page.reload();
  await loaded();
}
async function mode(value) {
  if (!(await page.locator("#turn-menu").evaluate((el) => el.open)))
    await page.locator("#turn-menu-button").click();
  await page.locator("#opponent").selectOption(value);
}
async function waitForHuman() {
  await page.waitForFunction(
    () => {
      const s = window.gridkick.getState();
      return (
        (s.team === "blue" && s.phase === "roll") ||
        ["goal", "finished", "halftime"].includes(s.phase)
      );
    },
    null,
    { timeout: 20000 },
  );
}
function normal() {
  const s = G.kickoff(G.createGame(), 1, 3);
  Object.assign(s, {
    phase: "roll",
    opening: false,
    kickoffKind: null,
    team: "red",
    ball: { x: 5, y: 3 },
    selected: null,
    used: [],
    remaining: 0,
    roll: 0,
  });
  return s;
}
try {
  await mkdir("test-results", { recursive: true });
  await page.goto(`${base}/?qa`);
  await loaded();
  assert.equal(await page.locator("#opponent").inputValue(), "computer");
  assert.match(await page.locator("#red-name").textContent(), /CPU/);
  await mode("human");
  await page.reload();
  await loaded();
  assert.equal(await page.locator("#opponent").inputValue(), "human");
  // Older saves stay in their original two-player mode.
  await fixture(G.createGame(), undefined);
  // fixture's default is computer; explicitly remove the new field to model an old save.
  await page.evaluate(() => {
    const s = JSON.parse(localStorage.getItem("gridkick60-match-v2"));
    delete s.opponent;
    localStorage.setItem("gridkick60-match-v2", JSON.stringify(s));
  });
  await page.reload();
  await loaded();
  assert.equal(await page.locator("#opponent").inputValue(), "human");
  // A red kickoff runs automatically, without consuming normal rolls.
  await fixture(G.kickoff(G.createGame(), 1, 3));
  assert.equal(await page.locator("#primary").isDisabled(), true);
  assert.equal(await page.locator("#undo").isDisabled(), true);
  await page.screenshot({ path: "test-results/computer-desktop.png" });
  await waitForHuman();
  assert.deepEqual((await state()).rolls, { blue: 0, red: 0 });
  assert.equal((await state()).team, "blue");
  // Red rolls exactly once and completes a normal turn without human input.
  await fixture(normal());
  await waitForHuman();
  assert.deepEqual((await state()).rolls, { blue: 0, red: 1 });
  // Reload mid-turn resumes the existing roll, never rerolls it.
  await fixture(G.rollDie(normal(), 6));
  await page.waitForFunction(
    () => window.gridkick.getState().phase !== "select",
  );
  assert.equal((await state()).team, "red");
  await page.reload();
  await loaded();
  await waitForHuman();
  assert.deepEqual((await state()).rolls, { blue: 0, red: 1 });
  // Switching to Human cancels the running plan without changing the position.
  await fixture(G.kickoff(G.createGame(), 1, 6));
  await mode("human");
  const stopped = await state();
  await page.waitForTimeout(1000);
  assert.deepEqual(await state(), stopped);
  assert.equal(await page.locator("#opponent").inputValue(), "human");
  // Re-enable the AI to finish the same kickoff.
  await mode("computer");
  await waitForHuman();
  assert.deepEqual((await state()).rolls, { blue: 0, red: 0 });
  // Dialogs pause visible moves; confirming New match cancels the old task.
  await fixture(G.kickoff(G.createGame(), 1, 6));
  await page.locator("#new-game").click();
  const paused = await state();
  await page.waitForTimeout(800);
  assert.deepEqual(await state(), paused);
  await page.locator("#confirm-restart").click();
  await page.waitForTimeout(900);
  assert.equal((await state()).phase, "ready");
  assert.deepEqual((await state()).rolls, { blue: 0, red: 0 });
  // Computer placement alternates with the human's legal placement.
  await fixture(G.startPlacement(G.createGame(), 1, 6));
  await page.waitForFunction(
    () => window.gridkick.getState().pawns.length === 1,
  );
  assert.equal((await state()).team, "blue");
  const target = G.placementOptions(await state())[0];
  const point = await page.evaluate(
    (p) => window.gridkick.screenPosition(p.x, p.y),
    target,
  );
  await page.mouse.click(point.x, point.y);
  await page.waitForFunction(
    () => window.gridkick.getState().pawns.length === 3,
  );
  assert.equal((await state()).team, "blue");
  // A kickoff already trapped by a human is replanned from its original dice.
  const baseline = G.kickoff(G.createGame(), 1, 6),
    trapped = structuredClone(baseline);
  Object.assign(trapped, { ball: { x: 0, y: 0 }, direction: 5, curved: true });
  await fixture(trapped, "computer", baseline);
  await waitForHuman();
  assert.deepEqual((await state()).rolls, { blue: 0, red: 0 });
  // A goal stays visible until Continue, and the conceding human gets the restart.
  const goal = G.rollDie(normal(), 2);
  goal.pawns = [
    { id: "red-1", team: "red", x: 2, y: 2, keeper: false },
    { id: "blue-1", team: "blue", x: 8, y: 5, keeper: false },
  ];
  goal.ball = { x: 2, y: 2 };
  await fixture(goal);
  await waitForHuman();
  assert.equal((await state()).phase, "goal");
  assert.equal((await state()).score.red, 1);
  await page.locator("#primary").click();
  assert.equal((await state()).team, "blue");
  assert.equal((await state()).phase, "roll");
  // Halftime uses the designated team, then gives the human the next roll.
  const half = normal();
  Object.assign(half, {
    phase: "halftime",
    half: 1,
    openingTeam: "blue",
    halftimeTeam: "red",
    team: "red",
    rolls: { blue: 10, red: 10 },
  });
  await fixture(half);
  await page.locator("#primary").click();
  await page.waitForFunction(() => window.gridkick.getState().half === 2);
  await waitForHuman();
  assert.equal((await state()).half, 2);
  assert.deepEqual((await state()).rolls, { blue: 10, red: 10 });
  // The computer's last roll reaches full time and stops.
  const last = G.rollDie(normal(), 1);
  last.half = 2;
  last.rolls = { blue: 20, red: 20 };
  await fixture(last);
  await waitForHuman();
  assert.equal((await state()).phase, "finished");
  const done = await state();
  await page.waitForTimeout(500);
  assert.deepEqual(await state(), done);
  // The larger options menu remains usable on a small phone, including landscape.
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 844, height: 390 },
  ]) {
    await page.setViewportSize(viewport);
    await fixture(G.createGame());
    await page.locator("#turn-menu-button").click();
    const fits = await page.locator("#opponent").evaluate((el) => {
      const r = el.getBoundingClientRect();
      return (
        r.left >= 0 &&
        r.right <= innerWidth &&
        r.top >= 0 &&
        r.bottom <= innerHeight
      );
    });
    assert.ok(fits);
    await page.screenshot({
      path: `test-results/computer-menu-${viewport.width}.png`,
    });
    await mode("human");
  }
  assert.deepEqual(errors, []);
  console.log(
    "PASS: local AI worker, solo/two-player persistence, old saves, automatic roll/kickoff/moves, reload without reroll, cancellation, paused dialogs, new match, placement, recovery, scoring, halftime, full time, mobile menu, zero browser errors.",
  );
} catch (error) {
  await page.screenshot({ path: "test-results/ai-failure.png" });
  console.error("State:", JSON.stringify(await state()));
  throw error;
} finally {
  await browser.close();
}
