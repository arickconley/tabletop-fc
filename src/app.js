import * as Game from "./game.js";
import { Board } from "./board.js";
import { applyAction } from "./ai.js";

const $ = (id) => document.getElementById(id);
let state = Game.createGame(),
  history = [],
  baseline = null,
  rolling = false,
  opponent = "computer",
  aiTask = null,
  aiFailed = false,
  board;
const saveKey = "gridkick60-match-v2";
try {
  const saved = JSON.parse(localStorage.getItem(saveKey));
  if (saved?.version === 2 && saved.state?.pawns && saved.state?.log) {
    Game.legalTargets(saved.state);
    opponent = saved.opponent === "computer" ? "computer" : "human";
    state = saved.state;
    baseline = saved.baseline;
    history = Array.isArray(saved.history) ? saved.history : [];
  }
} catch {
  /* Storage is optional; a fresh match still works. */
}
const controlsMedia = matchMedia("(max-width: 760px), (pointer: coarse)");
let controlsPreference = null;
try {
  const saved = localStorage.getItem("gridkick60-direction-controls");
  if (saved === "true" || saved === "false")
    controlsPreference = saved === "true";
} catch {}
const showControls = () => controlsPreference ?? controlsMedia.matches;
function isComputerTurn() {
  return (
    opponent === "computer" &&
    state.team === "red" &&
    [
      "placement",
      "roll",
      "select",
      "run",
      "kick",
      "relocate",
      "review",
    ].includes(state.phase)
  );
}
function cancelComputer() {
  aiTask?.abort();
  aiTask = null;
  aiFailed = false;
}
function delay(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) return reject(new Error("Cancelled"));
    const abort = () => {
      clearTimeout(timer);
      reject(new Error("Cancelled"));
    };
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", abort);
      resolve();
    }, ms);
    signal.addEventListener("abort", abort, { once: true });
  });
}
async function waitForTable(task, ms = 350) {
  await delay(
    matchMedia("(prefers-reduced-motion: reduce)").matches ? 60 : ms,
    task.signal,
  );
  while (document.querySelector("dialog[open]") || document.hidden)
    await delay(100, task.signal);
  if (task !== aiTask || !isComputerTurn()) throw Error("Cancelled");
}
function computerPlan(snapshot, task) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL("./ai-worker.js", import.meta.url), {
      type: "module",
    });
    const finish = (error, plan) => {
      clearTimeout(timeout);
      task.signal.removeEventListener("abort", abort);
      worker.terminate();
      if (error) reject(error);
      else resolve(plan);
    };
    const abort = () => finish(new Error("Cancelled"));
    const timeout = setTimeout(
      () => finish(new Error("Computer took too long to plan.")),
      15000,
    );
    task.signal.addEventListener("abort", abort, { once: true });
    worker.onmessage = ({ data }) =>
      finish(data.error ? new Error(data.error) : null, data.plan);
    worker.onerror = () =>
      finish(new Error("The computer player could not start."));
    worker.postMessage(snapshot);
  });
}
function scheduleComputer() {
  if (aiTask || aiFailed || !isComputerTurn()) return;
  const task = new AbortController();
  aiTask = task;
  runComputer(task);
}
async function runComputer(task) {
  try {
    await waitForTable(task, 550);
    if (state.phase === "roll") {
      await rollAnimation(
        () =>
          apply((s) => Game.rollDie(s, die()), {
            remember: false,
            newBaseline: true,
          }),
        () => task === aiTask && !task.signal.aborted,
      );
      return;
    }
    let plan = await computerPlan(state, task);
    // Taking over a human's unfinished route may require undoing to its original
    // die roll. Never reroll or reset a different turn.
    if (
      !plan &&
      baseline &&
      baseline.team === state.team &&
      baseline.turn === state.turn &&
      baseline.roll === state.roll &&
      baseline.rolls.red === state.rolls.red
    ) {
      plan = await computerPlan(baseline, task);
      if (plan) {
        await waitForTable(task);
        apply(() => structuredClone(baseline), { remember: false });
      }
    }
    if (!plan?.length)
      throw Error(
        "No complete route found. Switch Red to Human to revise the turn.",
      );
    for (const action of plan) {
      await waitForTable(task);
      if (!apply((s) => applyAction(s, action), { remember: false }))
        throw Error("The computer could not complete this route.");
    }
  } catch (error) {
    if (!task.signal.aborted && task === aiTask) {
      aiFailed = true;
      $("feedback").textContent = error.message;
    }
  } finally {
    if (task === aiTask) {
      aiTask = null;
      render();
    }
  }
}
const title = (word) => word[0].toUpperCase() + word.slice(1);
function die() {
  const bytes = new Uint8Array(1);
  do {
    crypto.getRandomValues(bytes);
  } while (bytes[0] >= 252);
  return (bytes[0] % 6) + 1;
}
function duel() {
  let blue, red;
  do {
    blue = die();
    red = die();
  } while (blue === red);
  return [blue, red];
}
function save() {
  try {
    localStorage.setItem(
      saveKey,
      JSON.stringify({ version: 2, state, baseline, history, opponent }),
    );
  } catch {}
}
function showDie(n) {
  const dots = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };
  $("die")
    .querySelectorAll("span")
    .forEach((s, i) => s.classList.toggle("on", (dots[n] || []).includes(i)));
  $("die").classList.toggle("empty", !n);
  $("die").setAttribute("aria-label", n ? `Die shows ${n}` : "Die not rolled");
}
function apply(fn, { remember = true, newBaseline = false } = {}) {
  try {
    const next = fn(state);
    if (remember) history.push(structuredClone(state));
    else history = [];
    state = next;
    if (newBaseline) baseline = structuredClone(state);
    $("feedback").textContent = "";
    render();
    save();
    return true;
  } catch (error) {
    $("feedback").textContent = shortReason(error.message);
    return false;
  }
}
function clickCell(x, y) {
  if (rolling || isComputerTurn()) return;
  if (state.phase === "placement") return apply((s) => Game.placePawn(s, x, y));
  if (
    state.phase === "select" ||
    (state.phase === "run" && state.remaining === state.roll)
  ) {
    const pawn = Game.at(state, x, y);
    if (pawn?.team === state.team)
      return apply((s) => Game.selectPawn(s, pawn.id));
  }
  if (state.phase === "run") return apply((s) => Game.runStep(s, x, y));
  if (state.phase === "kick") return apply((s) => Game.kickStep(s, x, y));
  if (state.phase === "relocate") return apply((s) => Game.relocate(s, x, y));
}
try {
  board = new Board($("viewport"), clickCell);
  $("loading").remove();
} catch (error) {
  $("loading").textContent =
    "The 3D pitch could not start. Enable WebGL 2 / hardware acceleration in your browser, then reload.";
  console.error(error);
}

const phaseLabels = {
  ready: "SETUP",
  placement: "SETUP",
  roll: "ROLL",
  select: "MOVE",
  run: "MOVE",
  kick: "KICK",
  relocate: "RELOCATE",
  review: "REVIEW",
  goal: "GOAL",
  halftime: "HALFTIME",
  finished: "FULL TIME",
};
function shortReason(reason = "") {
  if (reason.includes("goal mouth"))
    return "Leave your goal mouth before ending.";
  if (reason.includes("2×2")) return "Only one runner can stay in your box.";
  if (reason.includes("open path"))
    return "Leave your opponent a path to the ball.";
  if (reason.includes("Kick the ball off"))
    return "Kick the ball off its pawn first.";
  if (reason.includes("relocation"))
    return "Move the runner out of the goal mouth first.";
  if (reason.includes("exact distance"))
    return "Kickoff must use its exact distance.";
  if (reason.includes("highlighted shot"))
    return "Choose a highlighted direction; one 45° bend per kick.";
  if (reason.includes("Run one highlighted"))
    return "Choose an adjacent highlighted square.";
  if (reason.includes("Only one pawn"))
    return "One runner per turn. Undo to change it.";
  return reason;
}
function render() {
  const { phase, team } = state;
  const teamName = title(team);
  const targets = Game.legalTargets(state);
  const computerTurn = isComputerTurn();
  const locked =
    computerTurn || ["goal", "halftime", "finished"].includes(phase);
  $("opponent").value = opponent;
  $("opponent").disabled = rolling;
  $("play-mode-label").textContent =
    opponent === "computer" ? "YOU · BLUE / CPU · RED" : "LOCAL TWO-PLAYER";
  $("red-name").textContent = opponent === "computer" ? "RED · CPU" : "RED";
  const normalAction =
    !state.opening && ["select", "run", "kick"].includes(phase);
  const endErrors =
    normalAction || phase === "review" ? Game.endTurnErrors(state) : [];
  const fullTime = state.rolls.blue === 20 && state.rolls.red === 20;
  const halfTime =
    state.half === 1 && state.rolls.blue === 10 && state.rolls.red === 10;
  document.body.dataset.team =
    phase === "finished" && state.winner ? state.winner : team;
  $("turn-label").textContent =
    phase === "finished"
      ? "FULL TIME"
      : `${teamName.toUpperCase()} · ${state.opening ? "KICKOFF" : phaseLabels[phase]}`;
  $("score-state").textContent =
    phase === "finished"
      ? "FULL TIME"
      : phase === "halftime"
        ? "HALFTIME"
        : phase === "goal"
          ? "GOAL!"
          : state.opening || ["ready", "placement"].includes(phase)
            ? "KICKOFF"
            : `TURN ${String(state.turn).padStart(2, "0")}`;
  $("match-period").textContent =
    phase === "finished"
      ? "20 ROLLS EACH"
      : `ROLLS · ${state.half === 1 ? "1ST" : "2ND"} HALF`;
  for (const color of ["blue", "red"]) {
    $(`${color}-score`).classList.toggle(
      "active",
      phase === "finished"
        ? !state.winner || state.winner === color
        : team === color,
    );
    document.querySelector(`#${color}-score .score`).textContent =
      state.score[color];
    $(`${color}-rolls`).textContent = `${state.rolls[color]} / 20`;
    $(`${color}-rolls`).setAttribute(
      "aria-label",
      `${title(color)}: ${state.rolls[color]} of 20 rolls used`,
    );
    $(`${color}-rolls`).title = `${state.rolls[color]} of 20 normal rolls used`;
  }
  let prompt = "",
    action = "End turn",
    enabled = false,
    hint = "";
  switch (phase) {
    case "ready":
      prompt = "Ready to play";
      action = "Kick off";
      enabled = true;
      break;
    case "placement": {
      const count = state.pawns.filter((p) => p.team === team).length;
      prompt = count ? "Place a runner" : "Place your keeper";
      action = `${state.pawns.length} / 10 placed`;
      break;
    }
    case "roll":
      prompt = "Roll the die";
      action = "Roll";
      enabled = true;
      break;
    case "select":
      prompt = "Choose a pawn";
      break;
    case "run":
      prompt = "Move or end turn";
      break;
    case "kick":
      prompt = "Choose a kick direction";
      if (state.opening) action = "Finish kickoff";
      if (!targets.length)
        hint =
          state.opening || endErrors.length
            ? "Route blocked. Undo to try again."
            : "Route blocked. You can end here.";
      break;
    case "relocate":
      prompt = "Move out of the goal mouth";
      hint = targets.length
        ? "Free relocation required."
        : "No free square. Undo to try again.";
      break;
    case "review":
      prompt = endErrors.length
        ? "Adjust your move"
        : state.opening
          ? "Kickoff complete"
          : "Ready to end turn";
      action = state.opening ? "Finish kickoff" : "End turn";
      enabled = endErrors.length === 0;
      break;
    case "halftime":
      prompt = `${teamName} kicks off`;
      action = "Kick off";
      enabled = true;
      break;
    case "goal":
      prompt = `${teamName} scores!`;
      action = fullTime ? "Full time" : halfTime ? "Halftime" : "Continue";
      enabled = true;
      break;
    case "finished":
      prompt = state.winner ? `${title(state.winner)} wins!` : "It’s a draw";
      action = "New match";
      enabled = true;
      break;
  }
  if (normalAction) enabled = endErrors.length === 0;
  if (endErrors.length) hint = shortReason(endErrors[0]);
  if (computerTurn) {
    prompt = aiFailed
      ? "Computer paused"
      : phase === "roll"
        ? "Computer is rolling"
        : phase === "placement"
          ? "Computer is placing"
          : "Computer is playing";
    hint = aiFailed ? "Switch Red to Human in ⋯ to revise this turn." : "";
    action = aiFailed ? "Paused" : "Playing…";
    enabled = false;
  }
  $("action-title").textContent = prompt;
  $("instruction").textContent = hint;
  $("instruction").hidden = !hint;
  $("primary").textContent = rolling ? "Rolling…" : action;
  $("primary").disabled = !enabled || rolling;
  $("primary").title = normalAction
    ? endErrors[0] ||
      `Discard ${state.remaining} unused step${state.remaining === 1 ? "" : "s"} and end this turn. This roll still counts.`
    : "";
  const hasBudget = ["select", "run", "kick", "relocate", "review"].includes(
    phase,
  );
  $("dice-area").hidden = !hasBudget && !rolling;
  $("budget-left").textContent = rolling
    ? "Rolling…"
    : phase === "relocate"
      ? "Free move"
      : state.opening
        ? `${state.remaining} to kick`
        : ["select", "run"].includes(phase)
          ? `${state.remaining} move${state.remaining === 1 ? "" : "s"} left`
          : `${state.remaining} step${state.remaining === 1 ? "" : "s"} left`;
  $("free-step").hidden = !state.free || phase !== "kick" || rolling;
  showDie(hasBudget ? state.roll : 0);
  if (state.opening) {
    $("die").setAttribute("aria-label", `Kickoff distance: ${state.roll}`);
    $("dice-area").title =
      `Blue ${state.lastDice[0]} · Red ${state.lastDice[1]}. Kick exactly the difference; no free steps or scoring.`;
  } else
    $("dice-area").title = hasBudget
      ? `Rolled ${state.roll}; ${state.remaining} paid steps remain.`
      : "";
  $("undo").disabled = !history.length || rolling || locked;
  $("reset-turn").disabled = !baseline || !history.length || rolling || locked;
  $("custom-setup").hidden = phase !== "ready";
  $("custom-setup").disabled = rolling;
  $("new-game").disabled = rolling;
  $("direction-toggle").checked = showControls();
  const tips = {
    ready:
      "Use the ready-made formation, or choose Place teams manually in the turn options menu.",
    placement:
      "Alternate placements: one center-ring runner, 2–3 runners on your half, and 1–2 on the far half. Keepers go first.",
    roll: "Roll once, then move one pawn. Unused points can be discarded by ending in a legal position.",
    select:
      "Click a pawn to move. Direction controls in the turn menu also show numbered pawn buttons.",
    run: "Run orthogonally. You can turn or retrace. Contact with the ball starts a kick immediately.",
    kick: state.opening
      ? `Kick exactly the roll difference, with no free steps or scoring. ${title(state.nextTurnTeam)} takes the next normal turn.`
      : "The first square is free. Each kick may bend once by 45°. Passes grant a fresh free square and bend; each pawn kicks only once per turn.",
    relocate:
      "A runner that kicks from its own goal mouth must move to an empty adjacent square, free of charge.",
    review:
      "Keep at most one runner in your own box and leave an opponent a path to the ball. End turn commits the position.",
    halftime: `${teamName} did not take the opening kickoff and takes this one. The starting formation is restored; scores carry over. Kickoff dice do not count toward your 20 rolls.`,
    goal: "Goals add to the score. The conceding team restarts at its center-ring pawn unless the half or match has ended.",
    finished: `Blue ${state.score.blue}–${state.score.red} Red. Both players completed 20 normal rolls. Equal scores are a draw.`,
  };
  $("coach").textContent = tips[phase];
  $("turn-count").textContent = ["ready", "placement"].includes(phase)
    ? "PRE-MATCH"
    : `TURN ${String(state.turn).padStart(2, "0")}`;
  $("match-log").replaceChildren(
    ...state.log.slice(0, 7).map((line) => {
      const el = document.createElement("li");
      el.textContent = line;
      return el;
    }),
  );
  renderDirections(targets);
  renderPawnPicker();
  board?.update(state);
  scheduleComputer();
}
function renderDirections(targets) {
  const pad = $("direction-pad");
  pad.replaceChildren();
  pad.hidden =
    isComputerTurn() ||
    !showControls() ||
    !["run", "kick", "relocate"].includes(state.phase);
  if (pad.hidden) return;
  const center =
    state.phase === "kick"
      ? state.ball
      : state.pawns.find((p) => p.id === (state.relocating || state.selected));
  const arrows = ["↖", "↑", "↗", "←", "•", "→", "↙", "↓", "↘"];
  for (let i = 0; i < 9; i++) {
    const dx = (i % 3) - 1,
      dy = Math.floor(i / 3) - 1;
    if (!dx && !dy) {
      const label = document.createElement("span");
      label.className = "pad-center";
      label.textContent = "●";
      pad.append(label);
      continue;
    }
    const x = center.x + dx,
      y = center.y + dy,
      t = targets.find((p) => p.x === x && p.y === y),
      button = document.createElement("button");
    button.textContent = arrows[i];
    button.disabled = !t || rolling;
    button.setAttribute(
      "aria-label",
      `${state.phase === "kick" ? "Kick" : "Move"} ${arrows[i]} to ${Game.inside(x, y) ? Game.cellName(x, y) : "goal"}`,
    );
    button.onclick = () => clickCell(x, y);
    pad.append(button);
  }
}
function renderPawnPicker() {
  let picker = $("pawn-picker");
  if (picker) picker.remove();
  if (state.phase !== "select" || !showControls() || isComputerTurn()) return;
  picker = document.createElement("div");
  picker.id = "pawn-picker";
  picker.className = "pawn-picker";
  for (const p of state.pawns.filter((p) => p.team === state.team)) {
    const button = document.createElement("button");
    button.textContent = p.keeper ? "K" : p.id.split("-")[1];
    button.setAttribute(
      "aria-label",
      `Select ${p.keeper ? "keeper" : `runner ${p.id.split("-")[1]}`} at ${Game.cellName(p.x, p.y)}`,
    );
    button.onclick = () => clickCell(p.x, p.y);
    picker.append(button);
  }
  $("pawn-choices").append(picker);
}
async function rollAnimation(action, valid = () => true) {
  if (rolling) return;
  rolling = true;
  render();
  $("die").classList.add("rolling");
  const interval = setInterval(() => showDie(die()), 70);
  await new Promise((resolve) =>
    setTimeout(
      resolve,
      matchMedia("(prefers-reduced-motion: reduce)").matches ? 80 : 550,
    ),
  );
  clearInterval(interval);
  $("die").classList.remove("rolling");
  rolling = false;
  if (valid()) action();
  else render();
}
$("primary").onclick = () => {
  if (rolling || isComputerTurn()) return;
  if (state.phase === "ready")
    rollAnimation(() =>
      apply((s) => Game.kickoff(s, ...duel()), {
        remember: false,
        newBaseline: true,
      }),
    );
  else if (state.phase === "roll")
    rollAnimation(() =>
      apply((s) => Game.rollDie(s, die()), {
        remember: false,
        newBaseline: true,
      }),
    );
  else if (["select", "run", "kick", "review"].includes(state.phase))
    apply(Game.commitTurn, { remember: false, newBaseline: false });
  else if (state.phase === "halftime")
    rollAnimation(() =>
      apply((s) => Game.halftimeKickoff(s, ...duel()), {
        remember: false,
        newBaseline: true,
      }),
    );
  else if (state.phase === "goal")
    apply(Game.continueAfterGoal, { remember: false });
  else if (state.phase === "finished") $("restart-dialog").showModal();
};
$("undo").onclick = () => {
  if (rolling || isComputerTurn()) return;
  if (history.length) {
    state = history.pop();
    $("feedback").textContent = "";
    render();
    save();
  }
};
$("reset-turn").onclick = () => {
  if (rolling || isComputerTurn()) return;
  closeTurnMenu();
  if (baseline) {
    state = structuredClone(baseline);
    history = [];
    $("feedback").textContent = "";
    render();
    save();
  }
};
$("custom-setup").onclick = () => {
  closeTurnMenu();
  rollAnimation(() =>
    apply((s) => Game.startPlacement(s, ...duel()), {
      remember: false,
      newBaseline: true,
    }),
  );
};
$("new-game").onclick = () => $("restart-dialog").showModal();
$("confirm-restart").onclick = () => {
  cancelComputer();
  state = Game.createGame();
  history = [];
  baseline = null;
  $("restart-dialog").close();
  $("feedback").textContent = "";
  render();
  save();
};
$("rules-button").onclick = () => $("rules").showModal();
$("notes-button").onclick = () => $("notes-dialog").showModal();
async function toggleFullscreen() {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  } catch {
    $("feedback").textContent =
      "Fullscreen isn't available here. The game still fills your browser window.";
  }
}
$("fullscreen").onclick = toggleFullscreen;
if (!document.fullscreenEnabled) {
  $("fullscreen").disabled = true;
  $("fullscreen").title = "Fullscreen is unavailable in this browser";
}
document.addEventListener("fullscreenchange", () => {
  const active = !!document.fullscreenElement;
  $("fullscreen").setAttribute("aria-pressed", String(active));
  $("fullscreen").setAttribute(
    "aria-label",
    active ? "Exit fullscreen" : "Enter fullscreen",
  );
  $("fullscreen").title = active
    ? "Exit fullscreen (Esc or F)"
    : "Enter fullscreen (F)";
  board?.resize();
});
document.addEventListener("keydown", (event) => {
  if (
    event.key.toLowerCase() !== "f" ||
    event.ctrlKey ||
    event.metaKey ||
    event.altKey ||
    event.repeat ||
    document.querySelector("dialog[open]") ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName) ||
    !document.fullscreenEnabled
  )
    return;
  event.preventDefault();
  toggleFullscreen();
});
document
  .querySelectorAll(".close-dialog")
  .forEach(
    (button) => (button.onclick = () => button.closest("dialog").close()),
  );
for (const [id, view] of [
  ["perspective", "perspective"],
  ["top-view", "top"],
])
  $(id).onclick = () => {
    closeTurnMenu();
    board?.setView(view);
    $("perspective").classList.toggle("active", view === "perspective");
    $("top-view").classList.toggle("active", view === "top");
    $("perspective").setAttribute(
      "aria-pressed",
      String(view === "perspective"),
    );
    $("top-view").setAttribute("aria-pressed", String(view === "top"));
  };
function closeTurnMenu(restoreFocus = false) {
  const focusedInside = $("turn-menu-panel").contains(document.activeElement);
  $("turn-menu").open = false;
  if (restoreFocus || focusedInside) $("turn-menu-button").focus();
}
$("turn-menu").addEventListener("toggle", () => {
  $("turn-menu-button").setAttribute(
    "aria-expanded",
    String($("turn-menu").open),
  );
});
document.addEventListener("pointerdown", (event) => {
  if (!$("turn-menu").contains(event.target)) closeTurnMenu();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && $("turn-menu").open) {
    event.preventDefault();
    closeTurnMenu(true);
  }
});
$("opponent").onchange = (event) => {
  if (rolling) return;
  cancelComputer();
  opponent = event.target.value;
  $("feedback").textContent = "";
  closeTurnMenu();
  save();
  render();
};
$("direction-toggle").onchange = (event) => {
  controlsPreference = event.target.checked;
  try {
    localStorage.setItem(
      "gridkick60-direction-controls",
      String(controlsPreference),
    );
  } catch {}
  render();
};
controlsMedia.addEventListener("change", () => {
  if (controlsPreference === null) render();
});
document.addEventListener("keydown", (e) => {
  if (
    document.querySelector("dialog[open]") ||
    ["INPUT", "TEXTAREA", "SELECT", "BUTTON", "SUMMARY"].includes(
      document.activeElement?.tagName,
    ) ||
    rolling ||
    isComputerTurn()
  )
    return;
  const directions = {
    ArrowLeft: [-1, 0],
    ArrowRight: [1, 0],
    ArrowUp: [0, -1],
    ArrowDown: [0, 1],
  };
  if (directions[e.key] && ["run", "kick", "relocate"].includes(state.phase)) {
    e.preventDefault();
    const p =
      state.phase === "kick"
        ? state.ball
        : state.pawns.find(
            (p) => p.id === (state.relocating || state.selected),
          );
    const [dx, dy] = directions[e.key];
    clickCell(p.x + dx, p.y + dy);
  }
});
render();
// Opt-in read-only hooks for automated browser checks; absent in ordinary play.
if (new URLSearchParams(location.search).has("qa"))
  window.gridkick = {
    getState: () => structuredClone(state),
    screenPosition: (x, y) => board.screenPosition(x, y),
  };
