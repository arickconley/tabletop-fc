// Match menus stay separate from the rules engine and never advance a turn.
export function createScreens({
  snapshot,
  pause,
  resume,
  start,
  options,
  changeOptions,
  fullscreen,
  present,
}) {
  const $ = (id) => document.getElementById(id);
  const dialog = $("game-screens");
  let current = "home",
    parent = "home",
    pendingMode = "computer",
    confettiTimer,
    introTimer;
  const labels = {
    home: "home-title",
    pause: "pause-title",
    options: "options-title",
    credits: "credits-title",
    results: "results-title",
  };

  function show(name) {
    pause();
    current = name;
    clearTimeout(confettiTimer);
    $("confetti").replaceChildren();
    document.body.dataset.screen = name;
    present(name);
    clearTimeout(introTimer);
    $("match-intro").hidden = true;
    for (const panel of dialog.querySelectorAll("[data-panel]"))
      panel.hidden = panel.dataset.panel !== name;
    dialog.setAttribute("aria-labelledby", labels[name]);
    sync();
    if (!dialog.open) dialog.showModal();
    dialog.scrollTop = 0;
    const focus =
      name === "home"
        ? snapshot().hasMatch
          ? $("continue-match")
          : $("start-ai")
        : name === "pause"
          ? $("resume-match")
          : name === "results"
            ? $("play-again")
            : dialog.querySelector(`[data-panel="${name}"] .screen-back`);
    focus?.focus({ preventScroll: true });
  }
  function close() {
    clearTimeout(confettiTimer);
    $("confetti").replaceChildren();
    dialog.close();
    delete document.body.dataset.screen;
  }
  function resumeGame() {
    if (snapshot().state.phase === "finished") return results();
    close();
    resume();
    $("pause-button").focus({ preventScroll: true });
  }
  function requestNew(mode) {
    pendingMode = mode;
    if (snapshot().hasMatch && snapshot().state.phase !== "finished") {
      $("restart-dialog").showModal();
    } else newGame();
  }
  function newGame() {
    $("restart-dialog").close();
    close();
    start(pendingMode);
    if (!options().reducedMotion) {
      $("match-intro").hidden = false;
      introTimer = setTimeout(() => {
        $("match-intro").hidden = true;
      }, 850);
    }
    $("primary").focus({ preventScroll: true });
  }
  function sync() {
    const { state, opponent, hasMatch } = snapshot();
    $("continue-match").hidden = !hasMatch;
    $("continue-label").textContent =
      state.phase === "finished" ? "View match result" : "Continue match";
    $("saved-summary").textContent =
      `${opponent === "computer" ? "Vs computer" : "Local multiplayer"} · Blue ${state.score.blue}–${state.score.red} Red · ${state.phase === "finished" ? "Full time" : state.half === 1 ? "First half" : "Second half"}`;
    const settings = options();
    $("option-camera").value = settings.camera;
    $("option-directions").value = settings.directions;
    $("option-motion").value = settings.motion;
    $("option-celebrations").checked = settings.celebrations;
    $("option-fullscreen").disabled = !document.fullscreenEnabled;
    $("option-fullscreen").textContent = document.fullscreenElement
      ? "Exit fullscreen"
      : "Enter fullscreen";
  }
  function results() {
    const { state, opponent } = snapshot();
    const won =
      !!state.winner && (opponent === "human" || state.winner === "blue");
    show("results");
    dialog.dataset.outcome = !state.winner ? "draw" : won ? "win" : "loss";
    $("results-kicker").textContent = !state.winner
      ? "FULL TIME · ALL SQUARE"
      : won
        ? "FULL TIME · VICTORY"
        : "FULL TIME · DEFEAT";
    $("results-title").textContent = !state.winner
      ? "It's a draw!"
      : opponent === "computer" && won
        ? "You win!"
        : `${state.winner === "blue" ? "Blue" : "Red"} wins!`;
    $("results-message").textContent = !state.winner
      ? "Nothing between you. Settle it on the pitch again?"
      : won
        ? "A match to remember. The pitch is yours."
        : "The computer takes this one. Ready for a rematch?";
    $("results-blue").textContent = state.score.blue;
    $("results-red").textContent = state.score.red;
    $("results-red-label").textContent =
      opponent === "computer" ? "RED · COMPUTER" : "RED";
    $("results-blue-label").textContent =
      opponent === "computer" ? "BLUE · YOU" : "BLUE";
    $("result-blue-team").classList.toggle(
      "result-winner",
      state.winner === "blue",
    );
    $("result-red-team").classList.toggle(
      "result-winner",
      state.winner === "red",
    );
    $("results-trophy").toggleAttribute("hidden", !won);
    $("results-symbol").hidden = won;
    $("results-symbol").textContent = state.winner ? "FT" : "=";
    $("play-again").textContent =
      opponent === "computer"
        ? "Play again vs AI"
        : "Play again · local multiplayer";
    if (won && options().celebrations && !options().reducedMotion) {
      const colors = [
        "#d9ff43",
        "#ffffff",
        state.winner === "blue" ? "#78b6ee" : "#f38a75",
        "#83caa6",
      ];
      for (let i = 0; i < 48; i++) {
        const piece = document.createElement("i");
        piece.style.cssText = `--x:${(i * 37) % 100}%;--delay:${(i % 9) * 0.08}s;--drift:${(i % 2 ? 1 : -1) * (40 + (i % 80))}px;--spin:${180 + i * 19}deg;background:${colors[i % colors.length]}`;
        $("confetti").append(piece);
      }
      confettiTimer = setTimeout(() => $("confetti").replaceChildren(), 4800);
    }
  }
  $("start-ai").onclick = () => requestNew("computer");
  $("start-local").onclick = () => requestNew("human");
  $("continue-match").onclick = resumeGame;
  $("resume-match").onclick = resumeGame;
  $("new-game").onclick = () => requestNew(snapshot().opponent);
  $("confirm-restart").onclick = newGame;
  $("play-again").onclick = () => requestNew(snapshot().opponent);
  $("results-main-menu").onclick = $("pause-main-menu").onclick = () =>
    show("home");
  for (const button of dialog.querySelectorAll("[data-open-screen]"))
    button.onclick = () => {
      parent = current;
      show(button.dataset.openScreen);
    };
  for (const button of dialog.querySelectorAll(".screen-back"))
    button.onclick = () => show(parent);
  for (const [id, key] of [
    ["option-camera", "camera"],
    ["option-directions", "directions"],
    ["option-motion", "motion"],
  ])
    $(id).onchange = (event) => {
      changeOptions({ [key]: event.target.value });
      sync();
    };
  $("option-celebrations").onchange = (event) => {
    changeOptions({ celebrations: event.target.checked });
    sync();
  };
  $("option-fullscreen").onclick = fullscreen;
  document.addEventListener("fullscreenchange", sync);
  function back() {
    if (current === "pause") resumeGame();
    else if (["options", "credits"].includes(current)) show(parent);
  }
  dialog.addEventListener("keydown", (event) => {
    if (
      ["ArrowDown", "ArrowUp"].includes(event.key) &&
      ["home", "pause", "results"].includes(current)
    ) {
      const buttons = [
        ...dialog.querySelectorAll(
          `[data-panel="${current}"] button:not(:disabled)`,
        ),
      ].filter((el) => el.getClientRects().length);
      const index = buttons.indexOf(document.activeElement);
      const next =
        (index + (event.key === "ArrowDown" ? 1 : -1) + buttons.length) %
        buttons.length;
      event.preventDefault();
      buttons[next]?.focus();
      return;
    }
    if (event.key === "Tab") {
      const controls = [
        ...dialog.querySelectorAll(
          "button:not(:disabled), select:not(:disabled), input:not(:disabled), a[href]",
        ),
      ].filter((el) => el.getClientRects().length);
      const first = controls[0],
        last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
      return;
    }
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    back();
  });
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    back();
  });
  return {
    home: () => show("home"),
    pause: () => show("pause"),
    results,
    sync,
  };
}
