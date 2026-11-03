import test from "node:test";
import assert from "node:assert/strict";
import * as G from "../src/game.js";

function startMatch() {
  let s = G.kickoff(G.createGame(), 6, 4);
  s = G.kickStep(s, 5, 3);
  s = G.kickStep(s, 6, 3);
  return G.commitTurn(s);
}
function playKeeperTurn(s) {
  s = G.rollDie(s, 2);
  const keeper = s.pawns.find((p) => p.team === s.team && p.keeper);
  s = G.selectPawn(s, keeper.id);
  s = G.runStep(s, keeper.x + (s.team === "blue" ? 1 : -1), keeper.y);
  s = G.runStep(s, keeper.x, keeper.y);
  return G.commitTurn(s);
}
function atHalftime() {
  let s = startMatch();
  for (let i = 0; i < 20; i++) s = playKeeperTurn(s);
  return s;
}
function finishHalftime(s) {
  // Blue rolls higher, but red must still take the halftime kickoff.
  s = G.halftimeKickoff(s, 6, 4);
  s = G.kickStep(s, 4, 2);
  s = G.kickStep(s, 3, 2);
  return G.commitTurn(s);
}
function scoringTurn({
  rolls = { blue: 1, red: 0 },
  half = 1,
  score = { blue: 0, red: 0 },
} = {}) {
  const s = startMatch();
  Object.assign(s, {
    phase: "select",
    team: "blue",
    rolls,
    half,
    score,
    roll: 1,
    remaining: 1,
  });
  const runner = s.pawns.find((p) => p.id === "blue-4");
  runner.x = 8;
  runner.y = 3;
  s.ball = { x: 8, y: 3 };
  return G.kickStep(G.kickStep(G.selectPawn(s, runner.id), 9, 3), 10, 3);
}

test("a complete match has exactly 20 normal rolls per team and one halftime", () => {
  let s = startMatch();
  assert.deepEqual(s.rolls, { blue: 0, red: 0 });
  assert.equal(s.team, "red");
  assert.equal(s.openingTeam, "blue");
  for (let i = 0; i < 19; i++) s = playKeeperTurn(s);
  assert.deepEqual(s.rolls, { blue: 9, red: 10 });
  assert.equal(s.phase, "roll");
  s = playKeeperTurn(s);
  assert.equal(s.phase, "halftime");
  assert.deepEqual(s.rolls, { blue: 10, red: 10 });
  assert.throws(() => G.rollDie(s, 2));
  s = finishHalftime(s);
  assert.equal(s.team, "blue");
  assert.equal(s.half, 2);
  assert.deepEqual(s.rolls, { blue: 10, red: 10 });
  for (let i = 0; i < 19; i++) s = playKeeperTurn(s);
  assert.deepEqual(s.rolls, { blue: 20, red: 19 });
  assert.equal(s.phase, "roll");
  s = playKeeperTurn(s);
  assert.equal(s.phase, "finished");
  assert.deepEqual(s.rolls, { blue: 20, red: 20 });
  assert.equal(s.winner, null);
  assert.equal(s.turn, 40);
  assert.throws(() => G.rollDie(s, 1));
  assert.throws(() => G.halftimeKickoff(s, 4, 1));
});

test("halftime kicker is opposite the opening kicker, regardless of halftime dice", () => {
  const half = atHalftime();
  assert.equal(half.halftimeTeam, "red");
  assert.equal(half.team, "red");
  assert.throws(() => G.halftimeKickoff(half, 3, 3), /Tied/);
  for (const dice of [
    [6, 4],
    [1, 6],
  ]) {
    const s = G.halftimeKickoff(half, ...dice);
    assert.equal(s.team, "red");
    assert.equal(s.nextTurnTeam, "blue");
    assert.equal(s.remaining, Math.abs(dice[0] - dice[1]));
    assert.equal(s.opening, true);
    assert.equal(s.free, false);
    assert.deepEqual(s.rolls, { blue: 10, red: 10 });
  }
  const redOpening = G.kickoff(G.createGame(), 1, 6);
  assert.equal(redOpening.openingTeam, "red");
  assert.equal(redOpening.halftimeTeam, "blue");
});

test("the tenth roll finishes before halftime, and the twentieth before full time", () => {
  let s = startMatch();
  s.team = "blue";
  s.rolls = { blue: 9, red: 10 };
  s = G.rollDie(s, 1);
  assert.deepEqual(s.rolls, { blue: 10, red: 10 });
  assert.equal(s.phase, "select");
  assert.throws(() => G.halftimeKickoff(s, 5, 2));
  s = G.runStep(G.selectPawn(s, "blue-1"), 3, 1);
  assert.equal(s.phase, "review");
  assert.equal(G.commitTurn(s).phase, "halftime");
  s = startMatch();
  s.team = "blue";
  s.half = 2;
  s.rolls = { blue: 19, red: 20 };
  s = G.rollDie(s, 1);
  assert.equal(s.phase, "select");
  s = G.runStep(G.selectPawn(s, "blue-1"), 3, 1);
  assert.equal(s.phase, "review");
  assert.equal(G.commitTurn(s).phase, "finished");
});

test("normal roll counters cannot be rerolled or exceed either half's allowance", () => {
  const before = startMatch(),
    rolled = G.rollDie(before, 4);
  assert.deepEqual(before.rolls, { blue: 0, red: 0 });
  assert.deepEqual(rolled.rolls, { blue: 0, red: 1 });
  assert.throws(() => G.rollDie(rolled, 1));
  const moved = G.runStep(G.selectPawn(rolled, "red-1"), 6, 1);
  assert.deepEqual(moved.rolls, rolled.rolls);
  assert.deepEqual(G.commitTurn(moved).rolls, rolled.rolls);
  assert.deepEqual(rolled.rolls, { blue: 0, red: 1 }); // Reset/undo snapshots retain the used roll.
  for (const [half, used] of [
    [1, 10],
    [2, 20],
  ]) {
    const capped = { ...before, half, rolls: { blue: used, red: used } };
    assert.throws(() => G.rollDie(capped, 1), /every roll/);
  }
});

test("halftime preserves the score and restores the selected starting formation", () => {
  let s = startMatch();
  s.formation.find((p) => p.id === "blue-1").x = 1;
  s.pawns.find((p) => p.id === "blue-1").x = 6;
  s.score = { blue: 3, red: 2 };
  s.team = "blue";
  s.rolls = { blue: 9, red: 10 };
  s = playKeeperTurn(s);
  assert.equal(s.phase, "halftime");
  assert.deepEqual(s.pawns, s.formation);
  assert.equal(s.pawns.find((p) => p.id === "blue-1").x, 1);
  assert.deepEqual(s.score, { blue: 3, red: 2 });
  s = finishHalftime(s);
  assert.deepEqual(s.score, { blue: 3, red: 2 });
  assert.deepEqual(s.rolls, { blue: 10, red: 10 });
});

test("goals add to the score and restart the next normal turn without an extra roll", () => {
  let s = scoringTurn({ score: { blue: 2, red: 1 } });
  assert.equal(s.phase, "goal");
  assert.equal(s.winner, null);
  assert.deepEqual(s.score, { blue: 3, red: 1 });
  s = G.continueAfterGoal(s);
  assert.equal(s.phase, "roll");
  assert.equal(s.team, "red");
  assert.deepEqual(s.rolls, { blue: 1, red: 0 });
  assert.deepEqual(s.pawns, s.formation);
  const carrier = s.pawns.find((p) => p.team === "red" && G.same(p, s.ball));
  assert.ok(carrier && G.inRing(carrier.x, carrier.y));
  s = G.selectPawn(G.rollDie(s, 3), carrier.id);
  assert.equal(s.phase, "kick");
  assert.equal(s.free, true);
  assert.deepEqual(s.rolls, { blue: 1, red: 1 });
  assert.throws(() => G.continueAfterGoal(s));
});

test("a goal on the last first-half turn leads to halftime with the correct kicker", () => {
  let s = scoringTurn({ rolls: { blue: 10, red: 10 } });
  assert.equal(s.phase, "goal");
  s = G.continueAfterGoal(s);
  assert.equal(s.phase, "halftime");
  assert.equal(s.team, "red");
  assert.deepEqual(s.score, { blue: 1, red: 0 });
});

test("full time decides both winners and draws from the accumulated score", () => {
  for (const [score, winner] of [
    [{ blue: 4, red: 2 }, "blue"],
    [{ blue: 1, red: 3 }, "red"],
    [{ blue: 2, red: 2 }, null],
  ]) {
    let s = finishHalftime(atHalftime());
    s.rolls = { blue: 19, red: 20 };
    s.team = "blue";
    s.score = score;
    s = playKeeperTurn(s);
    assert.equal(s.phase, "finished");
    assert.equal(s.winner, winner);
    assert.deepEqual(s.score, score);
    assert.throws(() => G.rollDie(s, 6));
  }
});

test("a goal on the final turn counts before the final result", () => {
  let s = scoringTurn({
    rolls: { blue: 20, red: 20 },
    half: 2,
    score: { blue: 1, red: 2 },
  });
  assert.deepEqual(s.score, { blue: 2, red: 2 });
  s = G.continueAfterGoal(s);
  assert.equal(s.phase, "finished");
  assert.equal(s.winner, null);
  assert.deepEqual(s.rolls, { blue: 20, red: 20 });
});
