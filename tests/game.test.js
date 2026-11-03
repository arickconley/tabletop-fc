import test from "node:test";
import assert from "node:assert/strict";
import * as G from "../src/game.js";

const pawn = (id, team, x, y, keeper = false) => ({ id, team, x, y, keeper });
function scenario(pawns, ball, remaining = 3) {
  return {
    ...G.createGame(),
    phase: "select",
    team: "blue",
    pawns,
    ball,
    remaining,
    roll: remaining,
    used: [],
    opening: false,
  };
}
function shot(pawns, ball, remaining = 3) {
  let s = scenario(pawns, ball, remaining);
  return G.selectPawn(s, pawns[0].id);
}

test("default formation reproduces the PDF diagram and setup constraints", () => {
  const s = G.createGame();
  assert.equal(s.pawns.length, 10);
  for (const team of ["blue", "red"]) {
    const own = s.pawns.filter((p) => p.team === team),
      runners = own.filter((p) => !p.keeper);
    assert.equal(own.length, 5);
    assert.equal(runners.length, 4);
    assert.ok(G.inMouth(team, own[0].x, own[0].y));
    assert.equal(runners.filter((p) => G.ownHalf(team, p.x)).length, 3);
    assert.equal(runners.filter((p) => G.inRing(p.x, p.y)).length, 1);
  }
});
test("opening uses roll difference, has no free step, and gives the loser the next turn", () => {
  let s = G.kickoff(G.createGame(), 6, 4);
  assert.equal(s.remaining, 2);
  assert.equal(s.free, false);
  assert.equal(s.team, "blue");
  s = G.kickStep(s, 5, 3);
  assert.equal(s.remaining, 1);
  s = G.kickStep(s, 6, 3);
  assert.equal(s.phase, "review");
  s = G.commitTurn(s);
  assert.equal(s.team, "red");
  assert.equal(s.phase, "roll");
  assert.equal(s.turn, 1);
  assert.equal(s.opening, false);
});
test("tied opening rolls must be rerolled", () =>
  assert.throws(() => G.kickoff(G.createGame(), 3, 3), /Tied/));
test("run is orthogonal, cannot cross pawns, may retrace, and keeps one selected pawn", () => {
  let s = scenario(
    [pawn("a", "blue", 2, 2), pawn("b", "blue", 3, 2), pawn("c", "red", 8, 4)],
    { x: 5, y: 4 },
    4,
  );
  s = G.selectPawn(s, "a");
  assert.throws(() => G.runStep(s, 3, 3));
  assert.throws(() => G.runStep(s, 3, 2));
  s = G.runStep(s, 2, 3);
  assert.equal(s.remaining, 3);
  assert.throws(() => G.selectPawn(s, "b"), /Only one/);
  s = G.runStep(s, 2, 2);
  assert.equal(s.remaining, 2);
});
test("ball contact stops running and converts unused steps into a kick plus a free step", () => {
  let s = scenario(
    [pawn("a", "blue", 1, 1), pawn("b", "red", 8, 5)],
    { x: 3, y: 1 },
    3,
  );
  s = G.selectPawn(s, "a");
  s = G.runStep(s, 2, 1);
  s = G.runStep(s, 3, 1);
  assert.equal(s.phase, "kick");
  assert.equal(s.remaining, 1);
  assert.equal(s.free, true);
  assert.throws(() => G.runStep(s, 4, 1));
  s = G.kickStep(s, 4, 1);
  assert.equal(s.remaining, 1);
  s = G.kickStep(s, 5, 1);
  assert.equal(s.remaining, 0);
  assert.equal(s.phase, "review");
});
test("reaching the ball with zero steps still grants one free kick", () => {
  let s = scenario(
    [pawn("a", "blue", 1, 1), pawn("b", "red", 8, 5)],
    { x: 2, y: 1 },
    1,
  );
  s = G.runStep(G.selectPawn(s, "a"), 2, 1);
  assert.equal(s.remaining, 0);
  assert.equal(s.free, true);
  s = G.kickStep(s, 3, 1);
  assert.equal(s.phase, "review");
});
test("a kick may bend exactly once by 45°, never by 90°", () => {
  let s = shot(
    [pawn("a", "blue", 2, 2), pawn("b", "red", 9, 5)],
    { x: 2, y: 2 },
    3,
  );
  s = G.kickStep(s, 3, 2);
  assert.throws(() => G.kickStep(s, 3, 3));
  s = G.kickStep(s, 4, 3);
  assert.equal(s.curved, true);
  assert.throws(() => G.kickStep(s, 5, 3));
  s = G.kickStep(s, 5, 4);
  assert.equal(s.remaining, 1);
});
test("passes reset the bend and grant a free step, preserving paid steps", () => {
  let s = shot(
    [pawn("a", "blue", 2, 2), pawn("b", "blue", 4, 3), pawn("r", "red", 9, 5)],
    { x: 2, y: 2 },
    2,
  );
  s = G.kickStep(s, 3, 2);
  s = G.kickStep(s, 4, 3);
  assert.equal(s.selected, "b");
  assert.equal(s.curved, false);
  assert.equal(s.direction, null);
  assert.equal(s.free, true);
  assert.equal(s.remaining, 1);
  s = G.kickStep(s, 4, 2);
  assert.equal(s.remaining, 1);
  assert.deepEqual(s.used, ["a", "b"]);
});
test("free passes can chain even after the paid budget is exhausted", () => {
  let s = shot(
    [
      pawn("a", "blue", 2, 2),
      pawn("b", "blue", 3, 2),
      pawn("c", "blue", 4, 2),
      pawn("r", "red", 9, 5),
    ],
    { x: 2, y: 2 },
    0,
  );
  s = G.kickStep(s, 3, 2);
  s = G.kickStep(s, 4, 2);
  assert.equal(s.free, true);
  s = G.kickStep(s, 5, 2);
  assert.equal(s.phase, "review");
  assert.equal(s.remaining, 0);
});
test("defenders and previously used teammates block shots", () => {
  let s = shot(
    [pawn("a", "blue", 2, 2), pawn("b", "blue", 3, 2), pawn("r", "red", 4, 2)],
    { x: 2, y: 2 },
    3,
  );
  s = G.kickStep(s, 3, 2);
  assert.throws(() => G.kickStep(s, 4, 2));
  assert.throws(() => G.kickStep(s, 2, 2));
});
test("goals require crossing from the opponent mouth into the net", () => {
  let s = shot(
    [pawn("a", "blue", 8, 2), pawn("r", "red", 1, 4)],
    { x: 8, y: 2 },
    1,
  );
  s = G.kickStep(s, 9, 2);
  s = G.kickStep(s, 10, 2);
  assert.equal(s.phase, "goal");
  assert.equal(s.score.blue, 1);
  assert.equal(s.winner, null);
  const outside = shot(
    [pawn("a", "blue", 9, 0), pawn("r", "red", 1, 4)],
    { x: 9, y: 0 },
    1,
  );
  assert.throws(() => G.kickStep(outside, 10, 0));
  const above = shot(
    [pawn("a", "blue", 9, 2), pawn("r", "red", 1, 4)],
    { x: 9, y: 2 },
    1,
  );
  assert.throws(() => G.kickStep(above, 10, 1));
  const shortcut = shot(
    [pawn("a", "blue", 9, 1), pawn("r", "red", 1, 4)],
    { x: 9, y: 1 },
    1,
  );
  assert.throws(() => G.kickStep(shortcut, 10, 2));
});
test("red can score at the left net, but neither side can score an own goal", () => {
  let s = shot(
    [pawn("a", "blue", 0, 2), pawn("r", "red", 8, 4)],
    { x: 0, y: 2 },
    1,
  );
  assert.throws(() => G.kickStep(s, -1, 2));
  s = {
    ...s,
    team: "red",
    pawns: [pawn("a", "red", 0, 2), pawn("r", "blue", 8, 4)],
  };
  s = G.kickStep(s, -1, 2);
  assert.equal(s.score.red, 1);
  assert.equal(s.phase, "goal");
});
test("the opening kick cannot score or gain free steps on a pass", () => {
  let s = shot(
    [pawn("a", "blue", 9, 2), pawn("r", "red", 1, 4)],
    { x: 9, y: 2 },
    1,
  );
  s.opening = true;
  s.free = false;
  assert.throws(() => G.kickStep(s, 10, 2));
  s = shot(
    [pawn("a", "blue", 2, 2), pawn("b", "blue", 3, 2), pawn("r", "red", 9, 5)],
    { x: 2, y: 2 },
    2,
  );
  s.opening = true;
  s.free = false;
  s = G.kickStep(s, 3, 2);
  assert.equal(s.remaining, 1);
  assert.equal(s.free, false);
  s = G.kickStep(s, 4, 2);
  assert.equal(s.phase, "review");
  assert.equal(s.remaining, 0);
});
test("a keeper blocks the scoring lane", () => {
  const s = shot(
    [pawn("a", "blue", 8, 2), pawn("r", "red", 9, 2, true)],
    { x: 8, y: 2 },
    1,
  );
  assert.throws(() => G.kickStep(s, 9, 2));
});

test("a scoring turn must still respect the defensive box limit", () => {
  const s = shot(
    [
      pawn("a", "blue", 9, 3),
      pawn("b", "blue", 1, 2),
      pawn("c", "blue", 1, 3),
      pawn("r", "red", 8, 4),
    ],
    { x: 9, y: 3 },
    1,
  );
  assert.throws(() => G.kickStep(s, 10, 3));
});
test("a runner that kicks from its own mouth relocates for free", () => {
  let s = scenario(
    [pawn("a", "blue", 1, 2), pawn("r", "red", 8, 4)],
    { x: 0, y: 2 },
    1,
  );
  s = G.runStep(G.selectPawn(s, "a"), 0, 2);
  s = G.kickStep(s, 1, 2);
  assert.equal(s.phase, "relocate");
  assert.equal(s.remaining, 0);
  assert.throws(() => G.relocate(s, 0, 3)); // Still in the goal mouth.
  assert.throws(() => G.relocate(s, 1, 2)); // The ball cannot be occupied at turn end.
  s = G.relocate(s, 0, 1);
  assert.equal(s.phase, "review");
  assert.equal(s.remaining, 0);
  assert.deepEqual(G.turnErrors(s), []);
});
test("keeper may remain in the goal mouth after kicking", () => {
  let s = shot(
    [pawn("a", "blue", 0, 2, true), pawn("r", "red", 8, 4)],
    { x: 0, y: 2 },
    0,
  );
  s = G.kickStep(s, 1, 2);
  assert.equal(s.phase, "review");
  assert.deepEqual(G.turnErrors(s), []);
});
test("runners cannot finish a normal run in their own goal mouth", () => {
  let s = scenario(
    [pawn("a", "blue", 1, 2), pawn("r", "red", 8, 4)],
    { x: 5, y: 4 },
    1,
  );
  s = G.runStep(G.selectPawn(s, "a"), 0, 2);
  assert.equal(s.phase, "review");
  assert.match(G.turnErrors(s).join(), /goal mouth/);
  assert.throws(() => G.commitTurn(s));
});
test("two runners in their own box invalidate a turn", () => {
  const s = scenario(
    [
      pawn("a", "blue", 1, 2),
      pawn("b", "blue", 1, 3),
      pawn("k", "blue", 0, 2, true),
      pawn("r", "red", 8, 4),
    ],
    { x: 5, y: 4 },
  );
  assert.match(G.turnErrors(s).join(), /2×2/);
});
test("reachability detects an enclosed ball and allows arbitrarily long paths", () => {
  let s = scenario(
    [pawn("a", "blue", 1, 0), pawn("b", "blue", 0, 1), pawn("r", "red", 9, 5)],
    { x: 0, y: 0 },
  );
  assert.equal(G.opponentCanReachBall(s), false);
  s.pawns[0].x = 2;
  assert.equal(G.opponentCanReachBall(s), true);
});
test("trapped and untrapped runners can finish with unused steps", () => {
  let s = scenario(
    [pawn("a", "blue", 0, 0), pawn("b", "blue", 1, 0), pawn("c", "red", 0, 1)],
    { x: 6, y: 4 },
    4,
  );
  s = G.selectPawn(s, "a");
  assert.equal(s.phase, "review");
  assert.equal(s.remaining, 4);
  assert.equal(G.commitTurn(s).team, "red");
  s = G.selectPawn(
    scenario(
      [pawn("a", "blue", 2, 2), pawn("r", "red", 8, 4)],
      { x: 6, y: 4 },
      4,
    ),
    "a",
  );
  assert.equal(G.commitTurn(s).team, "red");
});
test("manual placement alternates teams and enforces a complete legal formation", () => {
  const defaultPawns = G.createGame().pawns;
  let s = G.startPlacement(G.createGame(), 6, 1);
  assert.equal(s.team, "blue");
  assert.equal(G.placementOptions(s).length, 2);
  assert.throws(() => G.placePawn(s, 3, 3));
  for (let i = 0; i < 5; i++)
    for (const team of ["blue", "red"]) {
      const p = defaultPawns.find((p) => p.id === `${team}-${i}`);
      s = G.placePawn(s, p.x, p.y);
    }
  assert.equal(s.phase, "ready");
  assert.equal(s.pawns.length, 10);
  assert.equal(G.kickoff(s, 1, 6).team, "red");
});
test("transitions preserve previous state for undo", () => {
  const s = G.createGame(),
    serialized = JSON.stringify(s);
  G.kickoff(s, 6, 1);
  assert.equal(JSON.stringify(s), serialized);
});
