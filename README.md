# Tabletop FC

A local Three.js adaptation of `Tabletop_FC_Rulebook.pdf`. Play solo against the computer or share the screen with another player. Each player gets 20 normal rolls, with halftime after 10 each. The higher final score wins; tied scores are a draw.

## Run

Use Node.js 24 (configured in `mise.toml`), or Node.js 22.12 or newer. From this folder:

```sh
npm install
npm run dev
```

Open **http://localhost:8000** in a modern browser with WebGL 2 enabled. From another computer on the same network, use the **Network** URL printed by Vite, such as `http://10.0.1.54:8000`. `npm start` runs the same Node-based dev server.

[Vite](https://vite.dev/guide/) watches the project for changes: CSS updates live without resetting the game, while JavaScript and HTML edits automatically reload to the title screen, where Continue match restores your saved turn. Keep using the same hostname and port to retain your browser's saved match. Port 8000 is fixed; if another server is using it, stop that server before starting Vite.

The first dependency install requires internet access; after that, the game and dev server run locally without an account or network service. Three.js 0.180.0 and OrbitControls remain included under `vendor/three/`, with their MIT license. The rulebook PDF is a local reference under the ignored `docs/` folder and is not included in Git.

## Menus and match flow

The title screen uses the actual 3D pitch in a floodlit miniature stadium, with an arcade selection menu and sports typography. It appears on launch with **New AI game**, **Local multiplayer**, **Options**, and **Credits**. **Continue match** appears when a saved match is available; completed matches offer **View match result**. Starting another game asks before replacing an unfinished match.

During play, **Ⅱ** or **Esc** opens the pause menu: Resume match, Options, Restart match, and Main menu. The computer and pitch animation pause while you use these menus. Returning to the title screen preserves the match. Escape returns from Options/Credits, resumes from Pause, and leaves the title/results screens open until you choose an action. Keyboard focus stays within the active menu; Up/Down selects menu actions and Enter activates them. The stadium presentation preserves your gameplay camera, including changes made in Options. A brief Blue-versus-Red transition introduces new matches and is skipped with reduced motion.

At full time, a result screen shows the winner and final score, with **Play again** and **Main menu**. A solo Blue victory says **You win!**; a computer win is identified as a defeat. Local matches name the winning team, and ties have a separate draw screen. Victories show a trophy and a brief confetti celebration. Play again preserves the chosen mode and options and resets the match. A goal before full time continues the match normally.

The floodlit stadium stays visible during play, with tiered stands and blue/red perimeter lights. Each new goal triggers a short field-level camera dolly toward the scoring net, team-colored fireworks, and a broadcast goal graphic. **Skip celebration** returns immediately to play. The sequence restores your previous camera view, orbit, and zoom, then waits for **Continue** (or Halftime / Full time). Pausing ends the sequence without changing the score. Loading a saved goal does not replay its celebration.

The pieces are original cartoon footballers with oversized heads, five hairstyles, varied skin tones, numbered shirts, shorts, socks, and boots. Keepers wear contrasting shirts and gloves; team rings and number labels keep the board readable. Players turn and run between squares, kick the ball from their feet, and cheer toward the goal camera. Reduced motion uses still poses. The characters are built from local Three.js geometry and canvas textures, without downloaded models or asset services.

Options save automatically: camera view, direction controls, motion, and celebration effects. Turning off celebration effects skips goal sequences and victory confetti. Reduced motion honors the device setting and can also be enabled explicitly; it skips goal sequences, disables confetti animation, and reduces piece/dice motion. Options and Credits are available before starting a match.

The menu flow follows the principles in Xbox's guidance on [consistent navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112), [protecting progress from destructive actions](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/115), and [motion settings](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117).

## Play

- Choose **Computer** or **Human** for the Red player in the **⋯** turn menu. In solo mode, you play **Blue** and the computer plays **Red**. The title screen selects the mode for a new match; saved matches keep their mode until you change it.
- Use the rulebook's illustrated lineup, or choose **Place teams manually** from the **⋯** turn menu. Manual setup alternates teams after a placement roll, keepers first.
- **Kick off** rolls both dice and rerolls ties. The winner's center-ring pawn kicks the difference; the loser takes the first regular turn.
- Roll, select a pawn, then click gold squares to run or kick one square at a time. Direction controls appear automatically on phones and touchscreens; toggle them in the **⋯** turn menu on any device. Your choice is saved in this browser. Arrow keys work when a control or dialog does not have focus.
- A kick starts automatically on reaching the ball. Passes grant a fresh free first step and a fresh bend. Every pawn can kick only once per turn.
- **End turn** lets you stop after rolling, during a run, or after a kick onto an empty square. Unused points are discarded; that roll still counts toward your 20. **Undo** and **Reset turn** (in the **⋯** menu) let you revise a route while keeping the original die roll. Gold squares are legal next steps, not a guarantee that the entire remaining route can be completed.
- Drag to orbit, scroll to zoom, or choose **2D** in the **⋯** menu for a view from above. Buttons marked 3D/2D change the camera, not the renderer.
- The die and remaining points share a compact readout. A **+1 free** badge marks a pending free kick step. The action bar shows one short prompt, with explanations when a rule blocks an action; **?** and match notes contain the details.
- The game fills the browser window, with the scoreboard and turn controls overlaid on the scene. The camera fits the pitch between the controls, including on phones and in landscape.
- Use the fullscreen button in the top-right corner or press **F** to enter/exit browser fullscreen. **Esc** also exits fullscreen. The top-right **?** opens the rules; **≡** opens match notes and tips; **Ⅱ** opens the pause menu. Restart match in that menu asks for confirmation.
- The current match is saved in this browser's local storage. **New match** clears it after confirmation. There is no backend or online multiplayer. The computer opponent runs entirely in your browser, with no account, API key, or network service.

## Computer opponent

The computer rolls once per normal turn, plans a complete legal route, and plays its moves on the pitch. It looks for goals and passes, advances the ball, considers possession and danger near its own goal, and can end early. It follows the same movement, kick, relocation, kickoff, and 20-roll rules as a human.

Start opening and halftime kickoffs with **Kick off**; the computer plays the kickoff when Red is the designated kicker. Choose **Continue** after a goal. Manual setup works too: the computer places Red's pieces automatically.

The planner runs in a Web Worker so the pitch and menus remain responsive. Moves pause while a dialog is open or the tab is hidden. Switching Red to Human or starting a new match cancels pending AI work. Reloading resumes the saved position and die roll. If you hand the computer an unfinished route that cannot be completed, it can revise from the start of that same roll.

This is a bounded tactical search with one difficulty level, not a trained model or an unbeatable opponent. If it cannot find a legal completion, it pauses and lets you take over via the Red player setting.

## Match length and halftime

The digital match now uses these house rules in place of the PDF’s first-goal-wins format:

- Each player gets **20 normal die rolls**, split into two halves of ten. The scoreboard shows each player's used rolls. A roll counts when rolled, but its entire turn is played before halftime or full time. Undo and reset retain that roll.
- Opening and halftime kickoff dice do **not** consume normal rolls. The opening kickoff still uses the winner of two dice; ties are rerolled.
- After both players complete roll ten, the starting formation (including manual setups) is restored and the score carries over. The team that **did not take the opening kickoff** takes the halftime kickoff, regardless of which team rolls higher at halftime. Both dice determine the absolute-difference kick distance; ties are rerolled. Kickoff has no free steps and cannot score.
- The other team takes the first normal turn after the halftime kickoff, then normal turns alternate until each has used 20 rolls.
- Goals add to the score and finish the current normal turn. Choose **Continue** to restore the starting formation and give the conceding team the ball at its center-ring pawn for its next normal turn. This restart does not grant an extra normal roll. If the goal completes a half or the match, go straight to halftime or full time instead.
- Finish both players' twentieth rolls before comparing scores. Higher score wins; equal scores end in a draw.

Matches use `tabletop-fc-match-v2`; options and direction controls use the same `tabletop-fc-` storage prefix. The Tabletop FC rename starts fresh saved matches and preferences. Saves from earlier editions remain untouched under their previous keys. Ending turns early works with existing Tabletop FC 20-roll saved matches.

## Rulebook mapping

The board has 10 columns and 6 rows. Internal coordinates are zero-based; displayed coordinates are A–F for rows and 1–10 for columns. Blue defends column 1, red column 10. The two goal-mouth squares are rows C and D on each end. The center ring consists of C5, D5, C6, and D6. The original formation is reproduced from page 2.

Implemented rules include orthogonal running and retracing, collision blocking, mandatory ball contact, an optional die-step budget, one free first kick square, eight shot directions, one 45° bend per kick, chained passes, once-per-turn kickers, goal-line scoring, keeper privileges, free runner relocation, the one-runner defensive-box limit, and the opponent's path-to-ball requirement.

The following interpretations make underspecified tabletop cases explicit:

- “Exactly the roll difference” takes precedence for the opening kick: no leg of an opening pass chain receives a free step. A pass on the last opening step cannot be completed because its receiver must redirect; undo and finish on an empty square instead.
- The ring contains the four central squares shown in the diagram. Manual setup uses exactly one center-ring runner per team, making the kickoff pawn unambiguous.
- Free goal-mouth relocation uses an orthogonally adjacent empty square outside the team's own mouth. It cannot land on the ball. Choose a different route if no such square exists.
- Normal turns can end before all steps are spent, provided the final position is legal. You cannot leave the ball on a pawn: contact and passes still require a kick, and required relocation must be completed. Opening and halftime kickoffs retain their exact-distance requirement. A blocked normal shot may end early if the position is legal; otherwise revise the route.

## Code and checks

- `src/game.js`: rendering-independent rules and immutable state transitions.
- `src/board.js`: Three.js scene, procedural pieces, lighting, camera, animation, and raycasting.
- `src/goal-camera.js`: temporary perspective goal camera and disposable firework particles; gameplay camera and match state remain independent.
- `src/players.js`: procedural footballer models, faces, kits, hairstyles, and running/kicking/celebration poses.
- `src/app.js`: turn controls, dice, history, local persistence, AI turn scheduling, and UI.
- `src/ai.js` and `src/ai-worker.js`: legal turn search, position evaluation, computer placement, and background planning.
- `src/style.css`: responsive in-game layout.
- `src/screens.js` and `src/screens.css`: title, pause, options, credits, results, and victory celebrations.
- `vite.config.js`: Node dev server, local-network access, and aliases for the vendored Three.js modules.
- `tests/game.test.js`: movement and kicking rules using Node's built-in test runner.
- `tests/match.test.js`: full 40-roll matches, halftime, score carryover, restarts, roll caps, and final results.
- `tests/early-turn.test.js`: voluntary early endings, unused points, required kicks/relocation, legal positions, and match boundaries.
- `tests/ai.test.js`: legal AI plans, scoring passes, relocation, kickoffs, and seeded full matches.
- `tests/ai-browser.mjs`: solo mode, automatic turns, cancellation, reloads, mode persistence, and match boundaries.
- `tests/screens-browser.mjs`: launch/continue, mode selection, pause, saved options, results, rematches, reduced motion, keyboard navigation, and responsive menus.
- `tests/goal-camera-browser.mjs`: real goals, camera restoration, fireworks cleanup, skip/pause, accessibility settings, phone resizing, and final-roll results.
- `tests/browser.mjs`: browser checks for rendering, pointer input, complete turns, undo/reset, persistence, setup, scoring, and mobile controls.

Run the rules and AI checks:

```sh
npm test
```

For optional browser checks, leave `npm run dev` running in another terminal, then run:

```sh
npx playwright install chromium
npm run test:browser
```

Playwright may require additional operating-system browser libraries on a minimal Linux installation. Screenshots are written to the ignored `test-results/` folder. `TABLETOP_FC_URL` overrides the test server URL. The `?qa` URL enables read-only state and board-coordinate hooks for these checks; ordinary play does not expose them.

Verified: 49 rules and AI tests plus Chromium checks for desktop, phone, and landscape layouts, native fullscreen and the F shortcut, unobscured board input, early endings, halftime, goal restarts, roll counters, and full-time wins and draws. No browser errors or external requests.

The renderer follows the official [Three.js installation documentation](https://threejs.org/manual/pages/installation.html) and uses [OrbitControls](https://threejs.org/docs/pages/OrbitControls). The pitch, stadium, pieces, and effects are procedural. Barlow Condensed is bundled under `vendor/fonts/barlow-condensed/` with its SIL Open Font License; there are no runtime font CDN or external asset requests.
