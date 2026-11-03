// Run a local server first. Install optional QA tools with npm install && npx playwright install chromium.
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
const page = await browser.newPage({
  viewport: { width: 1440, height: 1000 },
  reducedMotion: "reduce",
});
const errors = [],
  external = [];
page.on("pageerror", (error) => errors.push(error.message));
page.on("console", (msg) => {
  if (msg.type() === "error") errors.push(msg.text());
});
page.on("request", (request) => {
  if (!request.url().startsWith(base)) external.push(request.url());
});
const state = () => page.evaluate(() => window.gridkick.getState());
async function clickCell(x, y) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  const point = await page.evaluate(
    ([x, y]) => window.gridkick.screenPosition(x, y),
    [x, y],
  );
  await page.mouse.click(point.x, point.y);
  await page.waitForTimeout(60);
}
async function assertGameFits() {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  const layout = await page.evaluate(() => {
    const canvas = document
      .querySelector("#viewport canvas")
      .getBoundingClientRect();
    const controls = [
      "hud-header",
      "turn-dock",
      "primary",
      "undo",
      "turn-menu-button",
    ].map((id) => {
      const r = document.getElementById(id).getBoundingClientRect();
      return {
        id,
        visible:
          r.left >= 0 &&
          r.top >= 0 &&
          r.right <= innerWidth + 1 &&
          r.bottom <= innerHeight + 1,
      };
    });
    const cells = [
      [0, 0],
      [9, 0],
      [0, 5],
      [9, 5],
      [-1, 2],
      [10, 3],
    ];
    return {
      fullCanvas:
        canvas.x === 0 &&
        canvas.y === 0 &&
        Math.abs(canvas.width - innerWidth) < 1 &&
        Math.abs(canvas.height - innerHeight) < 1,
      noScroll:
        document.documentElement.scrollWidth <= innerWidth &&
        document.documentElement.scrollHeight <= innerHeight,
      controls,
      unobscured: cells.every(([x, y]) => {
        const p = window.gridkick.screenPosition(x, y);
        return document.elementFromPoint(p.x, p.y)?.tagName === "CANVAS";
      }),
    };
  });
  assert.ok(layout.fullCanvas, "Canvas fills the entire screen");
  assert.ok(layout.noScroll, "Game has no page scrolling");
  for (const control of layout.controls)
    assert.ok(control.visible, `${control.id} stays on screen`);
  assert.ok(
    layout.unobscured,
    "HUD leaves the pitch corners and goals clickable",
  );
}
async function turnOption(id) {
  if (!(await page.locator("#turn-menu").evaluate((el) => el.open)))
    await page.locator("#turn-menu-button").click();
  await page.locator(`#${id}`).click();
}
async function loadFixture(s) {
  await page.evaluate(
    (s) =>
      localStorage.setItem(
        "gridkick60-match-v2",
        JSON.stringify({ version: 2, state: s, baseline: s, history: [] }),
      ),
    s,
  );
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  await turnOption("top-view");
}
async function waitPhase(phase) {
  await page.waitForFunction(
    (phase) => window.gridkick.getState().phase === phase,
    phase,
  );
}
function plan(s, depth = 0) {
  if (s.phase === "goal" || (s.phase === "review" && !G.turnErrors(s).length))
    return [];
  if (depth > 24) return null;
  let options;
  if (s.phase === "select")
    options = s.pawns
      .filter((p) => p.team === s.team)
      .map((p) => ({ kind: "select", x: p.x, y: p.y, id: p.id }));
  else options = G.legalTargets(s).map((t) => ({ ...t, kind: s.phase }));
  // Prefer the ball, then goalward kicks. This is a QA route finder, not an in-game AI.
  options.sort((a, b) => {
    if (s.phase === "kick")
      return (
        (b.goal ? 100 : 0) -
        (a.goal ? 100 : 0) +
        (s.team === "blue" ? b.x - a.x : a.x - b.x)
      );
    return (
      Math.abs(a.x - s.ball.x) +
      Math.abs(a.y - s.ball.y) -
      Math.abs(b.x - s.ball.x) -
      Math.abs(b.y - s.ball.y)
    );
  });
  for (const action of options) {
    try {
      const next =
        action.kind === "select"
          ? G.selectPawn(s, action.id)
          : action.kind === "run"
            ? G.runStep(s, action.x, action.y)
            : action.kind === "kick"
              ? G.kickStep(s, action.x, action.y)
              : action.kind === "relocate"
                ? G.relocate(s, action.x, action.y)
                : null;
      if (!next) continue;
      const rest = plan(next, depth + 1);
      if (rest) return [action, ...rest];
    } catch {}
  }
  return null;
}
async function playPlan(s) {
  const actions = plan(s);
  assert.ok(actions, "A legal completion exists");
  for (const action of actions) await clickCell(action.x, action.y);
  const next = await state();
  assert.ok(
    next.phase === "review" || next.phase === "goal",
    `Route completed, got ${next.phase}: ${await page.locator("#feedback").textContent()}`,
  );
  return next;
}
try {
  await page.goto(`${base}/?qa`);
  await page.waitForFunction(() => !!window.gridkick);
  await page.locator("#turn-menu-button").click();
  await page.locator("#opponent").selectOption("human");
  assert.equal(await page.locator("#loading").count(), 0);
  await assertGameFits();
  await page.locator("#fullscreen").click();
  await page.waitForFunction(
    () =>
      !!document.fullscreenElement &&
      document.getElementById("fullscreen").getAttribute("aria-pressed") ===
        "true",
  );
  assert.equal(
    await page.locator("#fullscreen").getAttribute("aria-pressed"),
    "true",
  );
  await assertGameFits();
  await page.locator("#fullscreen").click();
  await page.waitForFunction(
    () =>
      !document.fullscreenElement &&
      document.getElementById("fullscreen").getAttribute("aria-pressed") ===
        "false",
  );
  assert.equal(
    await page.locator("#fullscreen").getAttribute("aria-pressed"),
    "false",
  );
  await page.keyboard.press("f");
  await page.waitForFunction(
    () =>
      !!document.fullscreenElement &&
      document.getElementById("fullscreen").getAttribute("aria-pressed") ===
        "true",
  );
  await page.keyboard.press("f");
  await page.waitForFunction(
    () =>
      !document.fullscreenElement &&
      document.getElementById("fullscreen").getAttribute("aria-pressed") ===
        "false",
  );
  await page.locator("#notes-button").click();
  assert.equal(
    await page.locator("#notes-dialog").evaluate((el) => el.open),
    true,
  );
  await page.getByRole("button", { name: "Close match notes" }).click();
  await mkdir("test-results", { recursive: true });
  await page.screenshot({ path: "test-results/desktop.png", fullPage: true });
  await page.locator("#rules-button").click();
  assert.equal(await page.locator("#rules").evaluate((el) => el.open), true);
  await page.keyboard.press("Escape");
  await page.locator("#primary").click();
  await waitPhase("kick");
  assert.equal(await page.locator("#direction-pad").isHidden(), true);
  const beforeControls = await state();
  await page.locator("#turn-menu-button").click();
  await page.locator("#direction-toggle").check();
  assert.equal(await page.locator("#direction-pad").isVisible(), true);
  assert.deepEqual(await state(), beforeControls);
  await page.keyboard.press("Escape");
  assert.equal(
    await page.locator("#turn-menu").evaluate((el) => el.open),
    false,
  );
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  assert.equal(await page.locator("#direction-pad").isVisible(), true);
  await page.locator("#turn-menu-button").click();
  await page.locator("#direction-toggle").uncheck();
  assert.equal(await page.locator("#direction-pad").isHidden(), true);
  await page.keyboard.press("Escape");
  await page.evaluate(() =>
    localStorage.removeItem("gridkick60-direction-controls"),
  );
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  assert.equal(await page.locator("#direction-pad").isHidden(), true);
  const opening = await state(),
    route = plan(opening);
  assert.ok(route?.length);
  // Exercise the perspective camera's actual board hit testing before switching views.
  await clickCell(route[0].x, route[0].y);
  assert.notDeepEqual((await state()).ball, opening.ball);
  await page.locator("#undo").click();
  assert.deepEqual((await state()).ball, opening.ball);
  await turnOption("top-view");
  await clickCell(route[0].x, route[0].y);
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  assert.equal(await page.locator("#undo").isEnabled(), true);
  await page.locator("#undo").click();
  assert.deepEqual((await state()).ball, opening.ball);
  await turnOption("top-view");
  await playPlan(await state());
  await page.locator("#primary").click();
  await waitPhase("roll");
  assert.equal((await state()).team, G.other(opening.team));
  for (let turn = 0; turn < 4; turn++) {
    await page.locator("#primary").click();
    await waitPhase("select");
    const rolled = await state(),
      actions = plan(rolled);
    assert.ok(actions?.length);
    await clickCell(actions[0].x, actions[0].y);
    await turnOption("reset-turn");
    assert.equal((await state()).phase, "select");
    assert.equal((await state()).roll, rolled.roll);
    assert.deepEqual((await state()).rolls, rolled.rolls);
    const next = await playPlan(await state());
    if (next.phase === "goal") break;
    await page.locator("#primary").click();
    await waitPhase("roll");
  }
  await page.locator("#new-game").click();
  await page.locator("#confirm-restart").click();
  await waitPhase("ready");
  await turnOption("custom-setup");
  await waitPhase("placement");
  for (let i = 0; i < 10; i++) {
    const s = await state(),
      index = s.pawns.filter((p) => p.team === s.team).length;
    const p = G.createGame().pawns.find((p) => p.id === `${s.team}-${index}`);
    await clickCell(p.x, p.y);
    assert.equal(
      (await state()).pawns.length,
      i + 1,
      `Placement ${i + 1} at ${G.cellName(p.x, p.y)}: ${await page.locator("#feedback").textContent()}`,
    );
  }
  await waitPhase("ready");
  // Ending early is offered after rolling, while running, and after a legal kick.
  const earlyBase = G.kickoff(G.createGame(), 6, 4);
  Object.assign(earlyBase, {
    phase: "roll",
    opening: false,
    kickoffKind: null,
    team: "blue",
    ball: { x: 6, y: 3 },
    selected: null,
    used: [],
    remaining: 0,
    roll: 0,
  });
  await loadFixture(G.rollDie(earlyBase, 6));
  assert.match(await page.locator("#primary").textContent(), /^End turn$/);
  assert.equal(await page.locator("#primary").isEnabled(), true);
  await page.locator("#primary").click();
  await waitPhase("roll");
  assert.equal((await state()).team, "red");
  assert.deepEqual((await state()).rolls, { blue: 1, red: 0 });
  await loadFixture(G.rollDie(earlyBase, 6));
  await clickCell(2, 1);
  await clickCell(3, 1);
  assert.equal((await state()).remaining, 5);
  assert.equal(
    await page.locator("#budget-left").textContent(),
    "5 moves left",
  );
  assert.equal(
    await page.locator("#die").getAttribute("aria-label"),
    "Die shows 6",
  );
  assert.equal(await page.locator("#instruction").isHidden(), true);
  await page.screenshot({ path: "test-results/compact-desktop.png" });
  await page.locator("#turn-menu-button").click();
  await page.screenshot({ path: "test-results/turn-menu.png" });
  await page.locator("#action-title").click();
  assert.equal(
    await page.locator("#turn-menu").evaluate((el) => el.open),
    false,
  );
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  assert.match(
    await page.locator("#primary").getAttribute("title"),
    /5 unused steps/,
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await assertGameFits();
  await page.screenshot({ path: "test-results/end-turn-early-mobile.png" });
  await page.locator("#primary").click();
  await waitPhase("roll");
  assert.equal((await state()).pawns.find((p) => p.id === "blue-1").x, 3);
  assert.deepEqual((await state()).rolls, { blue: 1, red: 0 });
  assert.equal(await page.locator("#undo").isDisabled(), true);
  await page.setViewportSize({ width: 1440, height: 1000 });
  const earlyKick = G.rollDie(earlyBase, 5);
  earlyKick.ball = { x: 2, y: 1 };
  await loadFixture(earlyKick);
  await clickCell(2, 1);
  await waitPhase("kick");
  assert.equal(await page.locator("#primary").isDisabled(), true);
  assert.match(
    await page.locator("#instruction").textContent(),
    /Kick the ball off/,
  );
  assert.equal(await page.locator("#free-step").isVisible(), true);
  await clickCell(3, 1);
  assert.equal((await state()).remaining, 5);
  assert.equal(
    await page.locator("#budget-left").textContent(),
    "5 steps left",
  );
  assert.equal(await page.locator("#free-step").isHidden(), true);
  assert.equal(await page.locator("#instruction").isHidden(), true);
  assert.equal(await page.locator("#primary").isEnabled(), true);
  await page.locator("#primary").click();
  await waitPhase("roll");
  assert.deepEqual((await state()).ball, { x: 3, y: 1 });
  const illegalEnd = G.rollDie(earlyBase, 6);
  illegalEnd.pawns.find((p) => p.id === "blue-1").x = 1;
  illegalEnd.pawns.find((p) => p.id === "blue-1").y = 2;
  await loadFixture(illegalEnd);
  await clickCell(1, 2);
  await clickCell(0, 2);
  assert.equal(await page.locator("#primary").isDisabled(), true);
  assert.match(await page.locator("#instruction").textContent(), /goal mouth/);
  for (const [half, count, phase] of [
    [1, 10, "halftime"],
    [2, 20, "finished"],
  ]) {
    const boundary = structuredClone(earlyBase);
    boundary.half = half;
    boundary.rolls = { blue: count - 1, red: count };
    await loadFixture(G.rollDie(boundary, 6));
    await page.locator("#primary").click();
    await waitPhase(phase);
    assert.deepEqual((await state()).rolls, { blue: count, red: count });
  }
  await loadFixture(G.kickoff(G.createGame(), 6, 4));
  assert.equal(await page.locator("#primary").isDisabled(), true);
  await clickCell(5, 3);
  assert.equal(await page.locator("#primary").isDisabled(), true);
  // A representative goal fixture uses the same saved-game format as normal reloads.
  let goal = G.kickoff(G.createGame(), 6, 4);
  goal.opening = false;
  goal.kickoffKind = null;
  goal.rolls = { blue: 1, red: 0 };
  goal.phase = "select";
  goal.roll = 1;
  goal.remaining = 1;
  goal.ball = { x: 8, y: 3 };
  goal.pawns.find((p) => p.id === "blue-4").x = 8;
  goal.pawns.find((p) => p.id === "blue-4").y = 3;
  goal = G.selectPawn(goal, "blue-4");
  await page.evaluate(
    (s) =>
      localStorage.setItem(
        "gridkick60-match-v2",
        JSON.stringify({ version: 2, state: s, baseline: s, history: [] }),
      ),
    goal,
  );
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  await turnOption("top-view");
  await clickCell(9, 3);
  await clickCell(10, 3);
  await waitPhase("goal");
  assert.equal(await page.locator("#blue-score .score").textContent(), "1");
  assert.equal(await page.locator("#undo").isDisabled(), true);
  await page.screenshot({ path: "test-results/goal.png", fullPage: true });
  await page.locator("#primary").click();
  await waitPhase("roll");
  assert.deepEqual((await state()).score, { blue: 1, red: 0 });
  assert.deepEqual((await state()).rolls, { blue: 1, red: 0 });
  assert.equal((await state()).team, "red");
  // Exercise the tenth roll, halftime kickoff, persistence, and 11th roll through the UI.
  let boundary = G.kickoff(G.createGame(), 6, 4);
  Object.assign(boundary, {
    phase: "roll",
    opening: false,
    kickoffKind: null,
    team: "blue",
    rolls: { blue: 9, red: 10 },
    score: { blue: 2, red: 1 },
    turn: 20,
    ball: { x: 6, y: 3 },
    selected: null,
    used: [],
  });
  await loadFixture(boundary);
  await page.locator("#primary").click();
  await waitPhase("select");
  assert.deepEqual((await state()).rolls, { blue: 10, red: 10 });
  await playPlan(await state());
  await page.locator("#primary").click();
  await waitPhase("halftime");
  const halftime = await state();
  assert.equal(halftime.team, "red");
  assert.equal(halftime.openingTeam, "blue");
  assert.deepEqual(halftime.pawns, halftime.formation);
  assert.equal(await page.locator("#red-rolls").textContent(), "10 / 20");
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  assert.equal((await state()).phase, "halftime");
  await page.screenshot({ path: "test-results/halftime.png" });
  await page.locator("#primary").click();
  await waitPhase("kick");
  assert.equal((await state()).team, "red");
  assert.equal((await state()).half, 2);
  assert.deepEqual((await state()).rolls, { blue: 10, red: 10 });
  assert.deepEqual((await state()).score, halftime.score);
  await turnOption("top-view");
  await playPlan(await state());
  await page.locator("#primary").click();
  await waitPhase("roll");
  assert.equal((await state()).team, "blue");
  await page.locator("#primary").click();
  await waitPhase("select");
  assert.deepEqual((await state()).rolls, { blue: 11, red: 10 });
  // The final die roll remains playable before the result is decided.
  boundary = G.kickoff(G.createGame(), 6, 4);
  Object.assign(boundary, {
    phase: "roll",
    opening: false,
    kickoffKind: null,
    half: 2,
    team: "red",
    rolls: { blue: 20, red: 19 },
    score: { blue: 2, red: 1 },
    turn: 40,
    ball: { x: 6, y: 3 },
    selected: null,
    used: [],
  });
  await loadFixture(boundary);
  await page.locator("#primary").click();
  await waitPhase("select");
  assert.deepEqual((await state()).rolls, { blue: 20, red: 20 });
  const finalTurn = await playPlan(await state());
  await page.locator("#primary").click();
  await waitPhase("finished");
  assert.deepEqual((await state()).score, finalTurn.score);
  assert.equal(
    (await state()).winner,
    finalTurn.score.blue > finalTurn.score.red
      ? "blue"
      : finalTurn.score.red > finalTurn.score.blue
        ? "red"
        : null,
  );
  assert.equal(await page.locator("#red-rolls").textContent(), "20 / 20");
  await page.reload();
  await page.waitForFunction(() => !!window.gridkick);
  assert.equal((await state()).phase, "finished");
  await page.screenshot({ path: "test-results/full-time.png" });
  boundary.phase = "review";
  boundary.remaining = 0;
  boundary.rolls = { blue: 20, red: 20 };
  boundary.score = { blue: 3, red: 3 };
  await loadFixture(boundary);
  await page.locator("#primary").click();
  await waitPhase("finished");
  assert.equal((await state()).winner, null);
  assert.match(await page.locator("#action-title").textContent(), /draw/i);
  await page.locator("#primary").click();
  await page.locator("#confirm-restart").click();
  await waitPhase("ready");
  await page.setViewportSize({ width: 390, height: 844 });
  await turnOption("perspective");
  await page.waitForTimeout(200);
  await assertGameFits();
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth > innerWidth,
    ),
    false,
  );
  await page.screenshot({ path: "test-results/mobile.png", fullPage: true });
  await page.locator("#primary").click();
  await waitPhase("kick");
  await assertGameFits();
  await page.screenshot({
    path: "test-results/mobile-kick.png",
    fullPage: true,
  });
  assert.equal(await page.locator("#direction-pad").isVisible(), true);
  const mobileRoute = plan(await state());
  assert.ok(mobileRoute?.length);
  for (const action of mobileRoute) {
    const label = `${G.inside(action.x, action.y) ? G.cellName(action.x, action.y) : "goal"}`;
    await page
      .locator("#direction-pad button")
      .filter({ hasText: /./ })
      .evaluateAll((buttons, label) => {
        const b = buttons.find((b) =>
          b.getAttribute("aria-label").endsWith(`to ${label}`),
        );
        if (!b || b.disabled) throw Error(`No direction to ${label}`);
        b.click();
      }, label);
  }
  await waitPhase("review");
  assert.equal(await page.locator("#primary").isEnabled(), true);
  for (const viewport of [
    { width: 844, height: 390 },
    { width: 320, height: 568 },
  ]) {
    await page.setViewportSize(viewport);
    await assertGameFits();
    await page.screenshot({
      path: `test-results/layout-${viewport.width}.png`,
    });
  }
  assert.deepEqual(errors, []);
  assert.deepEqual(external, []);
  console.log(
    "PASS: full-window canvas, fullscreen button and F shortcut, responsive HUD and unobscured pitch, desktop/mobile/landscape layouts, perspective and top-view raycasting, kickoff, four turns, undo, reset, reload persistence, manual placement, compact prompts, combined dice budget, optional direction controls, menu reset, early endings and invalid-stop guards, goals and restarts, halftime, fixed halftime kicker, roll counters, full time and draws, dialogs, mobile direction buttons, zero browser errors, zero external requests.",
  );
} catch (error) {
  await page.screenshot({ path: "test-results/failure.png", fullPage: true });
  console.error("Failure state:", JSON.stringify(await state()));
  throw error;
} finally {
  await browser.close();
}
