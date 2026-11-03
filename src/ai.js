import * as Game from "./game.js";

// Plans use the same transitions as human input. No simulated dice or rule shortcuts.
export function applyAction(state, action) {
  switch (action.kind) {
    case "select":
      return Game.selectPawn(state, action.id);
    case "run":
      return Game.runStep(state, action.x, action.y);
    case "kick":
      return Game.kickStep(state, action.x, action.y);
    case "relocate":
      return Game.relocate(state, action.x, action.y);
    case "end":
      return Game.commitTurn(state);
    case "place":
      return Game.placePawn(state, action.x, action.y);
    default:
      throw Error("Unknown computer action.");
  }
}

function actions(state) {
  if (state.phase === "select") {
    return state.pawns
      .filter((p) => p.team === state.team)
      .map((p) => ({ kind: "select", id: p.id }));
  }
  return Game.legalTargets(state).map(({ x, y }) => ({
    kind: state.phase,
    x,
    y,
  }));
}

function key(s) {
  return JSON.stringify([
    s.phase,
    s.remaining,
    s.selected,
    s.ball.x,
    s.ball.y,
    s.pawns.map((p) => [p.x, p.y]),
    s.used,
    s.direction,
    s.curved,
    s.free,
    s.relocating,
    s.resumePhase,
  ]);
}

function value(s, team) {
  if (s.phase === "goal") return 100000;
  const progress = team === "blue" ? s.ball.x : 9 - s.ball.x;
  const own = s.pawns.filter((p) => p.team === team);
  const enemy = s.pawns.filter((p) => p.team !== team);
  const distance = (p) => Math.abs(p.x - s.ball.x) + Math.abs(p.y - s.ball.y);
  const ours = Math.min(...own.map(distance));
  const theirs = Math.min(...enemy.map(distance));
  const central = Math.min(Math.abs(s.ball.y - 2), Math.abs(s.ball.y - 3));
  // Prefer territory, reachable possession and central shots. Keep a keeper at home.
  const keeper = own.find((p) => p.keeper);
  const exposed = keeper ? Math.abs(keeper.x - (team === "blue" ? 0 : 9)) : 0;
  const danger = Math.max(0, 4 - progress) * Math.max(0, 4 - theirs);
  return (
    progress * 7 -
    ours * 5 +
    Math.min(theirs, 6) * 2 -
    Math.max(0, ours - theirs) * 7 -
    central * 2 -
    exposed * 2 -
    danger * 3
  );
}

// Bounded beam search keeps mobile thinking time predictable. Only complete,
// legal turns compete for the result; partial routes never reach the UI.
export function planTurn(state, { width = 64, maxNodes = 18000 } = {}) {
  if (!["select", "run", "kick", "relocate", "review"].includes(state.phase))
    return null;
  const team = state.team;
  let best = null,
    bestValue = -Infinity,
    nodes = 0;
  let frontier = [{ state, path: [], score: value(state, team) }];
  const visited = new Set([key(state)]);
  for (let depth = 0; frontier.length && depth <= 28; depth++) {
    const next = [];
    for (const node of frontier) {
      const s = node.state;
      if (s.phase === "goal") return node.path;
      if (!Game.endTurnErrors(s).length) {
        const score = value(s, team) - node.path.length * 0.025;
        if (score > bestValue) {
          bestValue = score;
          best = [...node.path, { kind: "end" }];
        }
      }
      if (nodes >= maxNodes) continue;
      for (const action of actions(s)) {
        if (++nodes > maxNodes) break;
        const child = applyAction(s, action);
        const childKey = key(child);
        if (visited.has(childKey)) continue;
        visited.add(childKey);
        const path = [...node.path, action];
        if (child.phase === "goal") return path;
        // Ball contact is promising while searching, but cannot be an endpoint.
        const contact =
          Game.at(child, child.ball.x, child.ball.y)?.team === team;
        next.push({
          state: child,
          path,
          score: value(child, team) + (contact ? 14 : 0),
        });
      }
    }
    next.sort((a, b) => b.score - a.score || a.path.length - b.path.length);
    frontier = next.slice(0, width);
  }
  return best;
}

export function choosePlacement(state) {
  const options = Game.placementOptions(state);
  const count = state.pawns.filter((p) => p.team === state.team).length;
  const preferred = Game.createGame().pawns.find(
    (p) => p.id === `${state.team}-${count}`,
  );
  const target = options.find((p) => Game.same(p, preferred)) || options[0];
  return target ? { kind: "place", ...target } : null;
}
