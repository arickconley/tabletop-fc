import test from "node:test";
import assert from "node:assert/strict";
import * as G from "../src/game.js";
import { planTurn, applyAction, choosePlacement } from "../src/ai.js";

function finish(s) {
  const original = structuredClone(s);
  const plan = planTurn(s);
  assert.ok(
    plan?.length,
    `No plan for ${s.team} ${s.phase}, turn ${s.turn}, die ${s.roll}`,
  );
  assert.deepEqual(s, original, "Planning must not mutate the live match");
  for (const action of plan) s = applyAction(s, action);
  assert.ok(["roll", "goal", "halftime", "finished"].includes(s.phase));
  return s;
}
function turn(pawns, ball, roll = 3) {
  const s = G.kickoff(G.createGame(), 6, 4);
  Object.assign(s, {
    phase: "roll",
    opening: false,
    kickoffKind: null,
    team: "red",
    selected: null,
    used: [],
    pawns,
    ball,
  });
  return G.rollDie(s, roll);
}
const pawn = (id, team, x, y, keeper = false) => ({ id, team, x, y, keeper });

test("AI completes exact-distance kickoffs for either side and every distance", () => {
  for (const team of ["red", "blue"])
    for (let distance = 1; distance <= 5; distance++) {
      const s = G.kickoff(
        G.createGame(),
        team === "blue" ? distance + 1 : 1,
        team === "red" ? distance + 1 : 1,
      );
      const end = finish(s);
      assert.equal(end.team, G.other(team));
      assert.deepEqual(end.rolls, { blue: 0, red: 0 });
      assert.deepEqual(end.score, { blue: 0, red: 0 });
    }
});
test("AI takes an available goal instead of stopping early", () => {
  const s = turn(
    [pawn("r", "red", 2, 2), pawn("b", "blue", 8, 5)],
    { x: 2, y: 2 },
    2,
  );
  const end = finish(s);
  assert.equal(end.phase, "goal");
  assert.equal(end.score.red, 1);
});
test("AI finds a scoring pass with a fresh free step", () => {
  const s = turn(
    [pawn("r", "red", 3, 2), pawn("r2", "red", 2, 2), pawn("b", "blue", 8, 5)],
    { x: 3, y: 2 },
    2,
  );
  const plan = planTurn(s);
  const end = plan.reduce(applyAction, s);
  assert.equal(end.phase, "goal");
  assert.ok(end.used.includes("r2"));
});
test("AI completes required goal-mouth relocation and a legal endpoint", () => {
  let s = turn(
    [pawn("r", "red", 9, 2), pawn("b", "blue", 2, 5)],
    { x: 9, y: 2 },
    2,
  );
  s = G.kickStep(G.selectPawn(s, "r"), 8, 2);
  assert.equal(s.phase, "relocate");
  const end = finish(s);
  assert.equal(end.team, "blue");
  assert.equal(G.inMouth("red", end.pawns[0].x, end.pawns[0].y), false);
});
test("AI can end a blocked normal shot without spending its unused points", () => {
  let s = turn(
    [pawn("r", "red", 2, 1), pawn("b", "blue", 8, 5)],
    { x: 2, y: 1 },
    5,
  );
  s = G.kickStep(G.selectPawn(s, "r"), 1, 0);
  s = G.kickStep(s, 0, 0);
  assert.equal(G.legalTargets(s).length, 0);
  const end = finish(s);
  assert.deepEqual(end.ball, { x: 0, y: 0 });
  assert.equal(end.rolls.red, 1);
});
test("AI reports an impossible unfinished kickoff instead of breaking its rules", () => {
  let s = G.kickoff(G.createGame(), 1, 6);
  s.ball = { x: 0, y: 0 };
  s.direction = 5;
  s.curved = true;
  assert.equal(planTurn(s), null);
});
test("computer placement always follows the legal formation constraints", () => {
  let s = G.startPlacement(G.createGame(), 2, 5);
  while (s.phase === "placement") {
    const action = choosePlacement(s);
    assert.ok(action);
    s = applyAction(s, action);
  }
  assert.equal(s.pawns.length, 10);
  finish(G.kickoff(s, 1, 6));
});
test("seeded full matches finish with 20 rolls each, goals and the fixed halftime kicker", () => {
  for (let seed = 1; seed <= 3; seed++) {
    let random = seed;
    const die = () => {
      random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
      return (random % 6) + 1;
    };
    let s = G.kickoff(G.createGame(), seed % 2 ? 6 : 1, seed % 2 ? 1 : 6),
      steps = 0,
      halftime = false;
    while (s.phase !== "finished" && steps++ < 100) {
      if (s.phase === "roll") s = G.rollDie(s, die());
      else if (s.phase === "goal") s = G.continueAfterGoal(s);
      else if (s.phase === "halftime") {
        assert.deepEqual(s.rolls, { blue: 10, red: 10 });
        assert.equal(s.team, G.other(s.openingTeam));
        halftime = true;
        s = G.halftimeKickoff(s, 6, 1);
      } else s = finish(s);
    }
    assert.equal(s.phase, "finished");
    assert.ok(halftime);
    assert.deepEqual(s.rolls, { blue: 20, red: 20 });
    assert.ok(
      s.score.blue + s.score.red > 0,
      "The computer should create scoring chances",
    );
  }
});
