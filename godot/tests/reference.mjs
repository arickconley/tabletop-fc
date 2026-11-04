// Generate native-rule checks from the working web edition, including full matches.
import { writeFile } from "node:fs/promises";
import * as G from "../../src/game.js";
import { planTurn } from "../../src/ai.js";

const cases = [];
const clean = (state) => {
  const copy = structuredClone(state);
  delete copy.log;
  return copy;
};
function record(method, state, ...args) {
  let result;
  try { result = G[method](state, ...args); }
  catch { cases.push({ method, state: clean(state), args, invalid: true }); return; }
  cases.push({ method, state: clean(state), args, expected: clean(result), targets: G.legalTargets(result) });
  return result;
}

record("kickoff", G.createGame(), 2, 2);
record("kickoff", G.createGame(), 7, 1);
record("rollDie", G.createGame(), 3);
for (const rolls of [[6, 4], [1, 6]]) {
  let state = record("kickoff", G.createGame(), ...rolls);
  let turn = 0;
  while (state.phase !== "finished") {
    if (++turn > 100) throw Error("Reference match did not finish");
    if (state.phase === "halftime") state = record("halftimeKickoff", state, 6, 3);
    if (state.phase === "roll") state = record("rollDie", state, (turn % 6) + 1);
    record("runStep", state, -10, -10);
    const plan = planTurn(state);
    if (!plan) throw Error("No reference plan");
    for (const action of plan) {
      const method = { select: "selectPawn", run: "runStep", kick: "kickStep", relocate: "relocate", end: "commitTurn" }[action.kind];
      const args = action.kind === "select" ? [action.id] : action.kind === "end" ? [] : [action.x, action.y];
      state = record(method, state, ...args);
    }
    if (state.phase === "goal") state = record("continueAfterGoal", state);
  }
}

let state = G.kickoff(G.createGame(), 6, 4);
Object.assign(state, { phase: "select", opening: false, kickoffKind: null, roll: 1, remaining: 1, ball: { x: 8, y: 3 } });
Object.assign(state.pawns.find(p => p.id === "blue-4"), { x: 8, y: 3 });
state = record("selectPawn", state, "blue-4");
record("commitTurn", state);
state = record("kickStep", state, 9, 3);
state = record("kickStep", state, 10, 3);
record("continueAfterGoal", state);

state = G.kickoff(G.createGame(), 6, 4);
Object.assign(state, { phase: "select", opening: false, kickoffKind: null, roll: 2, remaining: 2, ball: { x: 0, y: 2 } });
Object.assign(state.pawns.find(p => p.id === "blue-1"), { x: 0, y: 2 });
state = record("selectPawn", state, "blue-1");
state = record("kickStep", state, 1, 2);
record("commitTurn", state);
record("relocate", state, 0, 1);

const path = process.argv[2] || "/tmp/tabletop-fc-rules.json";
await writeFile(path, JSON.stringify(cases));
console.log(`Wrote ${cases.length} reference transitions to ${path}`);
