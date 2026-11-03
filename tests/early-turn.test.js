import test from "node:test";
import assert from "node:assert/strict";
import * as G from "../src/game.js";

const pawn = (id, team, x, y, keeper = false) => ({ id, team, x, y, keeper });
function turn(
  pawns = [pawn("a", "blue", 1, 1), pawn("r", "red", 8, 5)],
  ball = { x: 4, y: 1 },
  n = 5,
) {
  const s = G.createGame();
  Object.assign(s, {
    phase: "roll",
    team: "blue",
    pawns,
    ball,
    openingTeam: "blue",
    halftimeTeam: "red",
    formation: structuredClone(G.createGame().pawns),
  });
  return G.rollDie(s, n);
}

test("ending before selecting a pawn discards steps but consumes exactly one roll", () => {
  const s = turn(),
    before = structuredClone(s);
  assert.deepEqual(G.endTurnErrors(s), []);
  const ended = G.commitTurn(s);
  assert.equal(ended.team, "red");
  assert.equal(ended.phase, "roll");
  assert.deepEqual(ended.rolls, { blue: 1, red: 0 });
  assert.deepEqual(ended.pawns, s.pawns);
  assert.deepEqual(ended.ball, s.ball);
  assert.equal(ended.remaining, 0);
  assert.equal(ended.roll, 0);
  assert.ok(ended.log.some((line) => line.includes("5 unused steps")));
  const next = G.rollDie(ended, 2);
  assert.equal(next.remaining, 2);
  assert.deepEqual(next.rolls, { blue: 1, red: 1 });
  assert.deepEqual(s, before);
});

test("ending midway through a run preserves the new position", () => {
  let s = G.runStep(G.selectPawn(turn(), "a"), 2, 1);
  assert.equal(s.phase, "run");
  assert.equal(s.remaining, 4);
  const ended = G.commitTurn(s);
  assert.deepEqual(ended.pawns, s.pawns);
  assert.deepEqual(ended.ball, { x: 4, y: 1 });
  assert.equal(ended.remaining, 0);
  assert.deepEqual(ended.rolls, { blue: 1, red: 0 });
});

test("a normal kick may stop on an empty square even when its route is blocked", () => {
  let s = turn([pawn("a", "blue", 7, 2), pawn("r", "red", 1, 1)], {
    x: 7,
    y: 2,
  });
  s = G.kickStep(G.selectPawn(s, "a"), 8, 2);
  s = G.kickStep(s, 9, 1);
  assert.equal(s.remaining, 4);
  assert.equal(G.kickOptions(s).length, 0);
  assert.deepEqual(G.endTurnErrors(s), []);
  const ended = G.commitTurn(s);
  assert.deepEqual(ended.ball, { x: 9, y: 1 });
  assert.equal(ended.team, "red");
});

test("ball contact and a receiving teammate must kick before ending early", () => {
  let s = turn(
    [pawn("a", "blue", 1, 1), pawn("b", "blue", 2, 1), pawn("r", "red", 8, 5)],
    { x: 1, y: 1 },
  );
  assert.throws(() => G.commitTurn(s), /Kick the ball off/);
  s = G.selectPawn(s, "a");
  assert.throws(() => G.commitTurn(s), /Kick the ball off/);
  s = G.kickStep(s, 2, 1);
  assert.equal(s.free, true);
  assert.throws(() => G.commitTurn(s), /Kick the ball off/);
  s = G.kickStep(s, 3, 1);
  assert.equal(s.remaining, 5);
  assert.deepEqual(G.endTurnErrors(s), []);
  assert.deepEqual(G.commitTurn(s).ball, { x: 3, y: 1 });
});

test("early endings still enforce goal-mouth, box, and opponent-path rules", () => {
  const mouth = G.selectPawn(
    turn([pawn("a", "blue", 0, 2), pawn("r", "red", 8, 5)]),
    "a",
  );
  assert.throws(() => G.commitTurn(mouth), /goal mouth/);
  const box = G.selectPawn(
    turn([
      pawn("a", "blue", 1, 2),
      pawn("b", "blue", 1, 3),
      pawn("r", "red", 8, 5),
    ]),
    "a",
  );
  assert.throws(() => G.commitTurn(box), /2×2/);
  const enclosed = G.selectPawn(
    turn(
      [
        pawn("a", "blue", 1, 0),
        pawn("b", "blue", 0, 1),
        pawn("r", "red", 8, 5),
      ],
      { x: 0, y: 0 },
    ),
    "a",
  );
  assert.throws(() => G.commitTurn(enclosed), /open path/);
});

test("a required relocation must finish before a turn can end early", () => {
  let s = turn(
    [pawn("a", "blue", 1, 2), pawn("r", "red", 8, 5)],
    { x: 0, y: 2 },
    2,
  );
  s = G.runStep(G.selectPawn(s, "a"), 0, 2);
  s = G.kickStep(s, 1, 2);
  assert.equal(s.phase, "relocate");
  assert.throws(() => G.commitTurn(s), /relocation/);
  s = G.relocate(s, 0, 1);
  assert.equal(s.remaining, 1);
  assert.deepEqual(G.endTurnErrors(s), []);
  assert.equal(G.commitTurn(s).team, "red");
});

test("neither kickoff can stop before its exact distance is spent", () => {
  let s = G.kickoff(G.createGame(), 6, 4);
  assert.throws(() => G.commitTurn(s), /exact distance/);
  s = G.kickStep(s, 5, 3);
  assert.throws(() => G.commitTurn(s), /exact distance/);
  s = G.kickStep(s, 6, 3);
  s = G.commitTurn(s);
  assert.equal(s.phase, "roll");
  Object.assign(s, { phase: "halftime", rolls: { blue: 10, red: 10 } });
  s = G.halftimeKickoff(s, 6, 4);
  assert.throws(() => G.commitTurn(s), /exact distance/);
  s = G.kickStep(s, 4, 2);
  assert.throws(() => G.commitTurn(s), /exact distance/);
  s = G.kickStep(s, 3, 2);
  assert.equal(G.commitTurn(s).phase, "roll");
});

test("early endings trigger halftime and full time at the same roll boundaries", () => {
  for (const [half, count, phase] of [
    [1, 10, "halftime"],
    [2, 20, "finished"],
  ]) {
    let s = turn();
    s.half = half;
    s.rolls = { blue: count, red: count };
    s.score = { blue: 2, red: 1 };
    s = G.runStep(G.selectPawn(s, "a"), 2, 1);
    const ended = G.commitTurn(s);
    assert.equal(ended.phase, phase);
    assert.deepEqual(ended.rolls, { blue: count, red: count });
    assert.deepEqual(ended.score, { blue: 2, red: 1 });
    if (half === 1) assert.equal(ended.team, "red");
    else assert.equal(ended.winner, "blue");
  }
});

test("a turn cannot be skipped before rolling or after it has ended", () => {
  for (const phase of [
    "ready",
    "placement",
    "roll",
    "goal",
    "halftime",
    "finished",
  ]) {
    const s = G.createGame();
    s.phase = phase;
    assert.throws(() => G.commitTurn(s), /roll must be in progress/);
  }
});
