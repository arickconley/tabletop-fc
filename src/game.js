export const WIDTH = 10,
  HEIGHT = 6;
export const ROLLS_PER_HALF = 10,
  ROLLS_PER_PLAYER = 20;
export const DIRECTIONS = [
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [-1, -1],
  [0, -1],
  [1, -1],
];
export const ORTHOGONAL = [
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];
export const other = (team) => (team === "blue" ? "red" : "blue");
export const inside = (x, y) => x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT;
export const same = (a, b) => a.x === b.x && a.y === b.y;
export const at = (s, x, y) => s.pawns.find((p) => p.x === x && p.y === y);
export const ownHalf = (team, x) => (team === "blue" ? x < 5 : x >= 5);
export const inRing = (x, y) => (x === 4 || x === 5) && (y === 2 || y === 3);
export const inMouth = (team, x, y) =>
  x === (team === "blue" ? 0 : 9) && (y === 2 || y === 3);
export const inBox = (team, x, y) =>
  (team === "blue" ? x <= 1 : x >= 8) && (y === 2 || y === 3);
const copy = (s) => structuredClone(s);
export const cellName = (x, y) => `${String.fromCharCode(65 + y)}${x + 1}`;
export function createGame() {
  const shape = {
    blue: [
      [0, 3],
      [2, 1],
      [2, 4],
      [4, 3],
      [6, 0],
    ],
    red: [
      [9, 2],
      [7, 1],
      [7, 4],
      [5, 2],
      [3, 5],
    ],
  };
  return {
    phase: "ready",
    team: "blue",
    pawns: Object.entries(shape).flatMap(([team, coords]) =>
      coords.map(([x, y], i) => ({
        id: `${team}-${i}`,
        team,
        keeper: i === 0,
        x,
        y,
      })),
    ),
    ball: { x: 4.5, y: 2.5 },
    remaining: 0,
    roll: 0,
    selected: null,
    used: [],
    direction: null,
    curved: false,
    free: false,
    opening: false,
    openingTeam: null,
    halftimeTeam: null,
    nextTurnTeam: null,
    kickoffKind: null,
    formation: null,
    half: 1,
    rolls: { blue: 0, red: 0 },
    score: { blue: 0, red: 0 },
    turn: 1,
    winner: null,
    trail: [],
    log: ["The rulebook formation is on the pitch."],
    lastDice: null,
  };
}
const note = (s, message) => {
  s.log = [message, ...s.log].slice(0, 40);
};
export function startPlacement(state, blue, red) {
  if (blue === red) throw Error("Tied placement rolls. Roll again.");
  const s = createGame();
  s.pawns = [];
  s.phase = "placement";
  s.team = blue > red ? "blue" : "red";
  s.lastDice = [blue, red];
  note(
    s,
    `${s.team} won the placement roll (${blue}–${red}). Place the keeper first.`,
  );
  return s;
}
export function placementOptions(s) {
  if (s.phase !== "placement") return [];
  const own = s.pawns.filter((p) => p.team === s.team),
    result = [];
  for (let y = 0; y < 6; y++)
    for (let x = 0; x < 10; x++) {
      if (at(s, x, y)) continue;
      if (!own.length) {
        if (inMouth(s.team, x, y)) result.push({ x, y });
        continue;
      }
      if (inMouth(s.team, x, y) || (!ownHalf(s.team, x) && inRing(x, y)))
        continue;
      const runners = [...own.filter((p) => !p.keeper), { x, y }];
      const home = runners.filter((p) => ownHalf(s.team, p.x)).length;
      const away = runners.length - home,
        ring = runners.filter((p) => inRing(p.x, p.y)).length,
        left = 4 - runners.length;
      if (
        home > 3 ||
        away > 2 ||
        home + left < 2 ||
        away + left < 1 ||
        ring > 1 ||
        ring + left < 1
      )
        continue;
      if (runners.filter((p) => inBox(s.team, p.x, p.y)).length > 1) continue;
      result.push({ x, y });
    }
  return result;
}
export function placePawn(state, x, y) {
  if (!placementOptions(state).some((p) => p.x === x && p.y === y))
    throw Error("Choose a highlighted setup square.");
  const s = copy(state),
    n = s.pawns.filter((p) => p.team === s.team).length;
  s.pawns.push({ id: `${s.team}-${n}`, team: s.team, keeper: n === 0, x, y });
  s.team = other(s.team);
  if (s.pawns.length === 10) {
    s.phase = "ready";
    note(s, "Both lineups are ready. Roll for kickoff.");
  }
  return s;
}
function beginKick(s, p, free = true) {
  s.selected = p.id;
  s.used.push(p.id);
  s.direction = null;
  s.curved = false;
  s.free = free;
  s.phase = "kick";
}
export function kickoff(state, blue, red) {
  if (state.phase !== "ready") throw Error("Finish setting up first.");
  validateKickoffDice(blue, red);
  const s = copy(state);
  s.formation = copy(s.pawns);
  s.openingTeam = blue > red ? "blue" : "red";
  s.halftimeTeam = other(s.openingTeam);
  s.kickoffKind = "opening";
  startKickoff(s, s.openingTeam, blue, red);
  note(
    s,
    `${s.team} wins kickoff ${blue}–${red}. Kick exactly ${s.remaining} squares; no free step or goal. Kickoff rolls do not count toward the 20.`,
  );
  return s;
}
function validateKickoffDice(blue, red) {
  if (![blue, red].every((n) => Number.isInteger(n) && n >= 1 && n <= 6))
    throw Error("A die must show 1–6.");
  if (blue === red) throw Error("Tied kickoff rolls. Roll again.");
}
function startKickoff(s, team, blue, red) {
  s.team = team;
  s.nextTurnTeam = other(team);
  s.opening = true;
  s.lastDice = [blue, red];
  s.remaining = Math.abs(blue - red);
  s.roll = s.remaining;
  s.used = [];
  const p = s.pawns.find(
    (p) => p.team === s.team && !p.keeper && inRing(p.x, p.y),
  );
  s.ball = { x: p.x, y: p.y };
  s.trail = [];
  beginKick(s, p, false);
}
export function halftimeKickoff(state, blue, red) {
  if (state.phase !== "halftime")
    throw Error("Halftime begins after both players finish 10 rolls.");
  validateKickoffDice(blue, red);
  const s = copy(state);
  s.half = 2;
  s.kickoffKind = "halftime";
  startKickoff(s, s.halftimeTeam, blue, red);
  note(
    s,
    `${s.team} takes the halftime kickoff. Kick exactly ${s.remaining} squares (${blue}–${red}); no free step or goal. Each player has 10 normal rolls left.`,
  );
  return s;
}
export function rollDie(state, n) {
  if (state.phase !== "roll") throw Error("Finish the current turn first.");
  if (!Number.isInteger(n) || n < 1 || n > 6)
    throw Error("A die must show 1–6.");
  const limit = state.half === 1 ? ROLLS_PER_HALF : ROLLS_PER_PLAYER;
  if (state.rolls[state.team] >= limit)
    throw Error("This player has used every roll in this half.");
  const s = copy(state);
  s.rolls[s.team]++;
  s.roll = n;
  s.remaining = n;
  s.phase = "select";
  s.used = [];
  s.selected = null;
  s.trail = [];
  s.lastDice = null;
  note(
    s,
    `${s.team} rolled ${n} (roll ${s.rolls[s.team]}/${ROLLS_PER_PLAYER}). Choose one pawn.`,
  );
  return s;
}
export function selectPawn(state, id) {
  if (!["select", "run"].includes(state.phase))
    throw Error("You cannot select a runner now.");
  if (state.phase === "run" && state.remaining !== state.roll)
    throw Error("Only one pawn can run each turn. Undo to change it.");
  const s = copy(state),
    p = s.pawns.find((p) => p.id === id && p.team === s.team);
  if (!p) throw Error("Choose a pawn on the active team.");
  s.selected = id;
  s.phase = "run";
  if (same(p, s.ball)) beginKick(s, p);
  else if (!runOptions(s).length) s.phase = "review";
  return s;
}
export function runOptions(s) {
  if (s.phase !== "run") return [];
  const p = s.pawns.find((p) => p.id === s.selected);
  return ORTHOGONAL.map(([dx, dy]) => ({ x: p.x + dx, y: p.y + dy })).filter(
    (p) => inside(p.x, p.y) && !at(s, p.x, p.y),
  );
}
export function runStep(state, x, y) {
  if (!runOptions(state).some((p) => p.x === x && p.y === y))
    throw Error("Run one highlighted square, without crossing another pawn.");
  const s = copy(state),
    p = s.pawns.find((p) => p.id === s.selected);
  s.trail.push({ x: p.x, y: p.y, kind: "run" });
  p.x = x;
  p.y = y;
  s.remaining--;
  if (same(p, s.ball)) {
    beginKick(s, p);
    note(
      s,
      `${s.team} reaches the ball. ${s.remaining} paid steps + one free step.`,
    );
  } else if (s.remaining === 0 || !runOptions(s).length) s.phase = "review";
  return s;
}
export function kickOptions(s) {
  if (s.phase !== "kick" || (!s.free && s.remaining <= 0)) return [];
  const result = [];
  DIRECTIONS.forEach(([dx, dy], dir) => {
    if (s.direction !== null) {
      const delta = Math.min(
        (dir - s.direction + 8) % 8,
        (s.direction - dir + 8) % 8,
      );
      if (delta !== 0 && (s.curved || delta !== 1)) return;
    }
    const x = s.ball.x + dx,
      y = s.ball.y + dy;
    if (!inside(x, y)) {
      const goalX = s.team === "blue" ? 10 : -1;
      if (
        !s.opening &&
        x === goalX &&
        (y === 2 || y === 3) &&
        inMouth(other(s.team), s.ball.x, s.ball.y) &&
        positionErrors(s).length === 0
      )
        result.push({ x, y, dir, goal: true });
      return;
    }
    const p = at(s, x, y);
    if (p && (p.team !== s.team || s.used.includes(p.id))) return;
    result.push({ x, y, dir, pass: !!p });
  });
  return result;
}
export function kickStep(state, x, y) {
  const option = kickOptions(state).find((p) => p.x === x && p.y === y);
  if (!option)
    throw Error(
      "Choose a highlighted shot direction. Each kick can bend once by 45°.",
    );
  const s = copy(state),
    kicker = s.pawns.find((p) => p.id === s.selected);
  s.trail.push({ ...s.ball, kind: "kick" });
  if (!s.free) s.remaining--;
  s.free = false;
  if (s.direction !== null && s.direction !== option.dir) s.curved = true;
  s.direction = option.dir;
  s.ball = { x, y };
  if (option.goal) {
    s.phase = "goal";
    s.score[s.team]++;
    note(s, `GOAL for ${s.team}! Blue ${s.score.blue}–${s.score.red} Red.`);
    return s;
  }
  const receiver = at(s, x, y);
  if (receiver) {
    beginKick(s, receiver, !s.opening);
    note(
      s,
      `Pass to ${receiver.keeper ? "keeper" : `runner ${receiver.id.split("-")[1]}`}. ${s.opening ? "Opening budget continues." : "Fresh free step; a new kick."}`,
    );
  } else if (s.remaining === 0) s.phase = "review";
  if (!kicker.keeper && inMouth(kicker.team, kicker.x, kicker.y)) {
    s.resumePhase = s.phase;
    s.relocating = kicker.id;
    s.phase = "relocate";
    note(
      s,
      "Move the runner out of its own goal mouth to an empty adjacent square, free of charge.",
    );
  }
  return s;
}
export function relocationOptions(s) {
  if (s.phase !== "relocate") return [];
  const p = s.pawns.find((p) => p.id === s.relocating);
  return ORTHOGONAL.map(([dx, dy]) => ({ x: p.x + dx, y: p.y + dy })).filter(
    (p) =>
      inside(p.x, p.y) &&
      !at(s, p.x, p.y) &&
      !same(p, s.ball) &&
      !inMouth(s.team, p.x, p.y),
  );
}
export function relocate(state, x, y) {
  if (!relocationOptions(state).some((p) => p.x === x && p.y === y))
    throw Error("Choose an empty adjacent square outside your goal mouth.");
  const s = copy(state),
    p = s.pawns.find((p) => p.id === s.relocating);
  p.x = x;
  p.y = y;
  s.phase = s.resumePhase;
  delete s.relocating;
  delete s.resumePhase;
  return s;
}
export function opponentCanReachBall(s) {
  const occupied = new Set(s.pawns.map((p) => `${p.x},${p.y}`));
  if (occupied.has(`${s.ball.x},${s.ball.y}`)) return false;
  const queue = s.pawns
    .filter((p) => p.team !== s.team)
    .map((p) => ({ x: p.x, y: p.y }));
  const visited = new Set(queue.map((p) => `${p.x},${p.y}`));
  for (let i = 0; i < queue.length; i++) {
    const p = queue[i];
    if (same(p, s.ball)) return true;
    for (const [dx, dy] of ORTHOGONAL) {
      const x = p.x + dx,
        y = p.y + dy,
        key = `${x},${y}`;
      if (inside(x, y) && !visited.has(key) && !occupied.has(key)) {
        visited.add(key);
        queue.push({ x, y });
      }
    }
  }
  return false;
}
function positionErrors(s) {
  const errors = [],
    runners = s.pawns.filter((p) => p.team === s.team && !p.keeper);
  if (runners.some((p) => inMouth(s.team, p.x, p.y)))
    errors.push(
      "A runner cannot finish in its own goal mouth. Move it out or undo to change the route.",
    );
  if (runners.filter((p) => inBox(s.team, p.x, p.y)).length > 1)
    errors.push(
      "Only one runner may finish in your own 2×2 defensive box. Move a runner out or undo to change the route.",
    );
  return errors;
}
export function turnErrors(s) {
  const errors = positionErrors(s);
  if (!opponentCanReachBall(s))
    errors.push(
      "An opponent must have an open path to the ball. Undo and leave a route.",
    );
  return errors;
}
export function endTurnErrors(s) {
  if (s.opening && (s.phase !== "review" || s.remaining !== 0))
    return ["Kickoffs must use their exact distance; they cannot end early."];
  if (s.phase === "relocate")
    return ["Complete the runner's free relocation before ending the turn."];
  if (!["select", "run", "kick", "review"].includes(s.phase))
    return ["A normal roll must be in progress before ending the turn."];
  if (at(s, s.ball.x, s.ball.y))
    return [
      "Kick the ball off its pawn before ending the turn; contact and passes still require a kick.",
    ];
  return turnErrors(s);
}
export function commitTurn(state) {
  const errors = endTurnErrors(state);
  if (errors.length) throw Error(errors[0]);
  const s = copy(state);
  if (s.opening) {
    s.team = s.nextTurnTeam;
    clearTurn(s);
    note(s, `${s.team} to play. Roll the die.`);
  } else {
    if (s.remaining > 0)
      note(
        s,
        `${s.team} ended the turn early, discarding ${s.remaining} unused step${s.remaining === 1 ? "" : "s"}. The roll still counts.`,
      );
    advanceNormalTurn(s);
  }
  return s;
}
function clearTurn(s) {
  s.opening = false;
  s.kickoffKind = null;
  s.nextTurnTeam = null;
  s.phase = "roll";
  s.selected = null;
  s.used = [];
  s.free = false;
  s.remaining = 0;
  s.roll = 0;
  s.lastDice = null;
  s.direction = null;
  s.curved = false;
  s.trail = [];
}
function resetFormation(s) {
  s.pawns = copy(s.formation || createGame().pawns);
  s.ball = { x: 4.5, y: 2.5 };
}
function advanceNormalTurn(s) {
  const next = other(s.team);
  clearTurn(s);
  if (s.rolls.blue === ROLLS_PER_PLAYER && s.rolls.red === ROLLS_PER_PLAYER) {
    s.phase = "finished";
    s.winner =
      s.score.blue === s.score.red
        ? null
        : s.score.blue > s.score.red
          ? "blue"
          : "red";
    note(
      s,
      `Full time. Blue ${s.score.blue}–${s.score.red} Red. ${s.winner ? `${s.winner} wins!` : "The match is a draw."}`,
    );
  } else if (
    s.half === 1 &&
    s.rolls.blue === ROLLS_PER_HALF &&
    s.rolls.red === ROLLS_PER_HALF
  ) {
    s.turn++;
    s.phase = "halftime";
    s.team = s.halftimeTeam;
    resetFormation(s);
    note(
      s,
      `Halftime: 10 rolls each. ${s.halftimeTeam} takes the kickoff because ${s.openingTeam} took the opening kickoff. The score carries over.`,
    );
  } else {
    s.turn++;
    s.team = next;
    note(s, `${s.team} to play. Roll the die.`);
  }
}
export function continueAfterGoal(state) {
  if (state.phase !== "goal") throw Error("There is no goal to restart from.");
  const s = copy(state);
  advanceNormalTurn(s);
  if (s.phase === "roll") {
    resetFormation(s);
    const receiver = s.pawns.find(
      (p) => p.team === s.team && !p.keeper && inRing(p.x, p.y),
    );
    s.ball = { x: receiver.x, y: receiver.y };
    note(
      s,
      `${s.team} restarts with the ball at its center-ring pawn. Roll for the next normal turn.`,
    );
  }
  return s;
}
export function legalTargets(s) {
  if (s.phase === "placement") return placementOptions(s);
  if (s.phase === "run") return runOptions(s);
  if (s.phase === "kick") return kickOptions(s);
  if (s.phase === "relocate") return relocationOptions(s);
  return [];
}
