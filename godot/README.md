# Tabletop FC — Godot

Native game, alongside the web game. Open `project.godot` in **Godot 4.7.2** and press **F5**. The project uses GDScript and the Mobile renderer.

## Play

The main menu presents **TABLE / TOP FC** over an empty stadium, with a groundskeeper wandering the pitch behind a mower. Choose **Play match** and the camera descends into the stadium’s locker room. Customize your team with **12 colours** and **Plain, Stripes, or Hoops** shirts on the player standing in the room, then choose **Computer** or **2 players**.

**Start match** follows that same player through the tunnel onto the pitch. A perspective camera travels just behind the captain's shoulder at player height, with a fixed lens while walking. After clearing the tunnel it physically rises and pulls back into the gameplay view. Teammates run into formation; only then do the kickoff dice appear. The opponent receives a random contrasting colour. Foreground locker-room and tunnel geometry fades out as the camera rises so it cannot obscure the pitch. Colours carry through the models, bases, highlights, dice, score labels, and turn prompts. Kit choices remain selected for the current app session.

Tap the 3D dice floating over the pitch to start the kickoff (reroll if tied). Every human turn opens with a central die: tap it, watch it tumble and settle on the result, then shrink beside the moves counter. The computer rolls and plays its own turns automatically, showing its route before the ball moves. The counter includes any free kick step. Eligible players have pulsing team-colored rings.

The main HUD keeps scores above the pitch and turn information below it. Primary actions use solid lime with dark text; secondary controls share the same navy surfaces and condensed typography as the menus. The dice have beveled meshes and pips on all six faces, including the small die beside the counter. Their animation settles on the value chosen by the match rules; it does not use physics to determine the roll.

Choose a highlighted player and tap outlined squares to run. Contact with the ball starts kick planning: select squares one at a time along the numbered arrows. **Confirm kick** appears as soon as the draft can legally finish; you do not need to tap its endpoint again. Press it to play the route. A legal route can finish early with moves left; kickoffs still require their exact distance. Passes must continue off the receiver, and required goal-mouth relocation is previewed before confirmation. The next player's dice appear when the ball finishes moving.

Use **Undo** to revise the turn one step at a time. It removes a relocation preview first, then the last planned kick step, then the last run step. At ball contact, with no kick draft, Undo moves the player back and restores the movement point. Tapping earlier route squares remains a shortcut: an earlier kick square rewinds the draft, and the ball's starting square clears it. Legal kick destinations take priority over run-history shortcuts, so the ball can travel through squares the player vacated. Confirmation ends the turn and clears its history. If you only run, **End turn** remains available when the position is legal. Players run with animated limbs and turning bodies; selection rings follow the moving model. The ball sits in front of its carrier and releases at the kick pose. Board input is locked during dice and ball animations.

The match menu has an overhead camera, rules, restart confirmation, and Pause / Options. Escape pauses play (or skips an active goal replay); a Pause button remains available during entrances, dice, and computer turns. Losing application focus pauses and saves the match. Options provide persistent Reduced motion and Mute sound settings, and the entrance can be skipped. Drag the pitch with one finger (or the left mouse button) to orbit the camera; drag upward to raise the angle and reveal squares behind players. Small finger jitter remains a tap, and releasing a drag never plays a move. Menu → Reset camera restores the default angle. Camera switches and resizing ease into the new view, while direct dragging follows the finger without inertia. Portrait view turns the pitch lengthways to make squares easier to tap. The HUD accounts for mobile safe areas and device scale, with a fixed feedback allowance so messages appearing or disappearing never reframe the pitch. There is no movement pad. At full time, a centered result presents the outcome and final score with **Play again** and **Main menu** actions. Play again immediately starts a rematch with the same kits and opponent. Solo results identify whether you or the computer won.

Goals trigger a short broadcast celebration: the camera moves down to replay the scorer's final kick in slow motion, the scoring team raises its arms, and team-coloured fireworks burst above the goal. The replay uses the actual shot route, including its bend, without replaying the rules or counting another goal. **Skip celebration** or **Escape** returns immediately. The original gameplay camera and overhead setting are restored before the next kickoff, halftime, or full-time result. Gameplay input is locked throughout the sequence.

Included rules: the default formation, opening and halftime kickoffs, orthogonal running, free kick steps, passing, one 45° bend per kick, goal-mouth relocation, defensive-box and opponent-path checks, goals and restarts, 20 rolls each, halftime, draws, and undo.

The miniature stadium includes rounded footballers with faces, varied hair and skin tones, numbered kits, boots, striped turf, goal nets, corner flags, tiered bleachers, spectators, railings, and floodlights. Foreground stands and towers fade with the active camera to keep the pitch clear; portrait framing prioritizes playable squares over fitting all the scenery. Models are generated locally, with shared materials and batched spectators; no downloaded model packs are required.

The computer works offline and uses the same rules and dice as the human. Its bounded search looks for scoring combinations, territory, nearby supporting runners, and keeper protection. It then checks the opponent’s likely reply for each of the six possible dice rolls across six shortlisted positions. It never reads the real next roll. Seeded move ordering and small tie-breaking variation avoid repeating comparable choices; a late lead increases the cost of allowing a counterattack. Search work runs in roughly 4 ms slices between frames. There is one difficulty level. The match is saved after actions, including the current roll, undo history, kick draft, kits, and opponent. Chosen dice and committed kick outcomes are saved before presentation, so an interruption cannot grant another roll or duplicate a goal. Continue match resumes from the home screen. Writes replace the previous save only after completion; invalid saves show a recovery message. Manual formations and web-save transfer are not implemented.

Keyboard play: use arrows to move a visible board cursor in screen directions, Enter/Space to choose a square, Z/Backspace to undo, and C to confirm a kick or end a turn. Tab moves through interface controls. Escape pauses or skips a replay.

Short synthesized sounds mark selections, dice, contact, kickoff, and goals. They can be muted in Options.

## Design direction

**Clean sports broadcast, playful tabletop.** The stadium, locker room, and toy footballers form one continuous world. The interface adds a restrained broadcast layer over it, using the same visual language from the main menu through kit selection, play, help, and the final result.

- Use deep navy surfaces, off-white text, and one lime accent for primary actions and selections. White focus rings distinguish keyboard focus from the selected choice. Team colours communicate ownership, with names and markers so colour is never the only cue.
- Keep Barlow Condensed throughout: expressive italic display type for the title and major outcomes, clear upright type for instructions and controls.
- Share button shapes, spacing, focus treatment, and selected states across screens. Keep primary actions prominent and secondary actions quieter, with touch targets at least 44 pixels wide and high.
- Keep scores and turn actions in stable positions around the playable pitch. Make Undo and confirmation visible controls; board gestures are optional shortcuts.
- Keep help and confirmations short, readable, and styled as part of the game. Preserve the stadium behind overlays instead of switching to unrelated presentation.

References reviewed on Interface In Game:

- [Rocket League — Garage](https://interfaceingame.com/screenshots/rocket-league-garage/): the featured character or vehicle and live arena can anchor a compact menu without losing the game's setting.
- [Armello — Action points](https://interfaceingame.com/screenshots/armello-action-points/): explain a specific turn resource close to the control it describes, keeping the board as the context.
- [Mario Kart Tour — Race Scoreboard](https://interfaceingame.com/screenshots/mario-kart-tour-race-scoreboard/): give results a clear outcome-first hierarchy that remains readable in portrait.

## Code

- `scripts/rules.gd`: rendering-independent port of `../src/game.js`. Transitions return a new state or `{ "error": message }`; callers must handle errors.
- `scripts/computer.gd`: incremental search of complete legal turns, seeded variation, and bounded opponent replies; never changes the live match. The native evaluation now differs from `../src/ai.js`.
- `scripts/team_lobby.gd`: main menu, locker-room kit controls, and game mode selection.
- `scripts/ui_theme.gd`: shared palette, typography, primary and secondary controls, selection states, and dialog surfaces.
- `scripts/goal_celebration.gd`: goal replay camera, scorer animation, fireworks, score overlay, skip, and visual-state restoration.
- `scripts/stadium_journey.gd`: physical locker room and tunnel, groundskeeper, camera travel, and the customized player's entrance into the match.
- `scripts/menu_backdrop.gdshader`: directional menu shading that leaves the stadium and locker-room player visible.
- `scripts/team_kits.gd`: named palette, shirt designs, and contrasting opponent selection. Internal blue/red rule IDs stay independent of appearance.
- `scripts/board.gd`: procedural pitch, movement animation, route previews, legal-square markers, picking, and camera fitting.
- `scripts/footballer.gd`: toy-style player models and their collision bodies.
- `scripts/stadium.gd`: bleachers, batched crowd, floodlights, and camera-dependent scenery visibility.
- `scripts/match_save.gd`: validated, versioned, atomic match persistence.
- `scripts/session_menu.gd`: pause, skip entrance, reduced motion, mute, and focus restoration.
- `scripts/match_audio.gd`: local synthesized sound cues.
- `scripts/match.gd`: native touch/mouse/keyboard input, kick drafts and confirmation, compact HUD, turn actions, undo, and menus.
- `scripts/turn_dice.gd`: tappable dice, result reveal, and the animation into the moves strip.
- `scripts/die.gd`: lit 3D dice, face orientation, tumbling, and transparent rendering for the prompt and counter.
- `scenes/match.tscn`: startup scene. Geometry and HUD are built at runtime.
- `assets/fonts`: Barlow Condensed, with its SIL Open Font License.

The installed MCP Toolkit addon belongs to the editor integration. Its bridge is `@npgamedev/godot-mcp-server@1.1.2`, not the separate `godot-ai` server. Point `GODOT_MCP_PROJECT_PATH` at this folder when the client starts from the parent repository.

## Adjust cameras in the 3D editor

Open `scenes/stadium_journey.tscn` directly, select a `Camera` under `Shots`, and enable **Preview** in the 3D viewport. Move the Camera with the transform gizmo; move its sibling **Target** to change where it looks. The camera aims at that target in both the editor and the game, so edit the Target rather than rotating the Camera. Adjust **FOV**, **H Offset**, and **V Offset** in the Camera inspector, then save the scene and press **F5** to run the game.

| Scene node | Controls |
| --- | --- |
| `Shots/Shoulder/Camera` and `Target` | Camera distance, shoulder height, side offset, aim, and lens while following the captain. Move these children, not the whole Shoulder rig, to change the follow offsets. |
| `Shots/LockerLandscape` / `LockerPortrait` | Separate locker-room compositions for desktop and phone. |
| `Shots/HomeLandscape` / `HomePortrait` | Stadium menu views. |
| `Shots/RoomApproach` | Intermediate camera position when entering/leaving the locker room. |
| `Blocking/CaptainStart`, `Door`, `PitchEntry` | Player start and walk-out destinations. |
| `LockerRoomAndTunnel` | Actual room/tunnel meshes and lights used by the game. |

`EditorPreview` contains reference stadium geometry and two stand-in captains for framing the shots. It is removed when the match starts; edits there do not alter gameplay models. The main pitch, crowd, and customizable footballers remain procedural. Gameplay framing still fits the screen automatically, using perspective so the entrance hands off without a projection change.

## Checks

From the repository root, with Godot 4.7.2 installed:

```sh
python3 scripts/test-native.py --godot /Applications/Godot.app/Contents/MacOS/Godot
# Optional GPU run and screenshots (use a foreground window on macOS):
python3 scripts/test-native.py ui celebration --rendered --captures /tmp/tabletop-ui --godot /path/to/godot
python3 scripts/test-native.py performance --rendered --godot /path/to/godot
```

The runner fixes the viewport, generates rule fixtures, and fails on script assertions or timeouts. `.github/workflows/native.yml` imports and runs all default checks on Linux for native changes. The `orbit` check covers touch-versus-drag separation, HUD gesture boundaries, rotated square picking, complete camera rotation at both tilt limits, reset, overhead, pause, and reduced motion. The `polish` check covers animated limbs/selection, facing-aware contact, save validation and recovery, resumed drafts, paused simulation, reduced motion, interrupted dice, keyboard input, instant rematches, and early entrance skipping.

The rule check compares 727 transitions and their legal targets against the existing JavaScript game, including complete matches. The native scene check covers central dice, ties, docking, compact layout, eligible players, movement, draft isolation, bends, passes, scoring, kickoff distance, relocation, automatic handoff, input locking, undo boundaries, halftime, and full time. No browser or Playwright is involved.

The computer checks cover both kickoff teams at every distance, scoring passes, required relocation, blocked shots, impossible routes, and three seeded full matches. The strategy check adds repeatable seeds, varied opening choices, mirrored-field balance, a legal counterattack trap, two-receiver scoring combinations, and total search-node bounds. Reply searches are capped at 900 nodes and 16 alternatives per depth; this is an estimate of the opponent’s options, not exhaustive minimax. The computer scene check covers mode selection, automatic rolls, animated playback, human input locking and handoff, halftime, cancellation, and local play.

The lobby check covers the empty pitch and moving groundskeeper, camera descent, all kit colours and designs, responsive controls, the same player traversing the tunnel, the camera handoff, final formation, input locking, colour propagation, and returning to the menu.

The UI check covers shared control styling, touch targets, kit scrolling, readable HUD labels, help, confirmation, and full-time layouts at 320×568, 390×844, 640×360, and 1280×800. With a screenshot directory after `--`, it captures each screen for visual review. Use `--headless` and omit the directory for layout assertions alone.

The celebration check covers both scoring directions, a goal after a pass, the final kicker and route, fireworks, input locking, score isolation, camera restoration, portrait resizing, skipping, and goals at halftime/full time. Its optional output directory captures the kick, replay, and fireworks.

## Native distribution

`export_presets.cfg` defines macOS (universal), Windows (x86_64), and iOS (project only), with bundle identifier **io.arick.tabletopfc** and version **1.0.0**. Matching **4.7.2 export templates** must be installed. Editor tools and tests are excluded from exports; the app uses the Tabletop FC icon.

```sh
python3 scripts/export-native.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

Outputs under `dist/native/`:

- `TabletopFC-macOS.zip`: app with local ad-hoc signing.
- `TabletopFC-Windows.zip`: unsigned executable with embedded game data.
- `TabletopFC-iOS-project.zip`: Xcode project, engine frameworks, and game data; unpack before opening `TabletopFC.xcodeproj`.
- Export logs and license notices.

The iOS preset uses **Arick Conley — team 9833XCBZ6Q**. The local Apple Development identity and existing team provisioning profile support the paired iPhone. The export helper generates the project only; Xcode signs the app for device installation. If a different checkout clears the team field, the helper temporarily supplies the field Godot requires and removes the placeholder after export.

To build a development-signed release and install it on the paired phone:

```sh
xcodebuild -project dist/native/ios/TabletopFC.xcodeproj -scheme TabletopFC \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/tabletop-ios-phone -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=9833XCBZ6Q CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' build
xcrun devicectl device install app --device aPhone \
  /tmp/tabletop-ios-phone/Build/Products/Release-iphoneos/TabletopFC.app
xcrun devicectl device process launch --device aPhone io.arick.tabletopfc
```

Apple [documents automatic signing and device provisioning](https://developer.apple.com/documentation/xcode/building-and-running-an-app). The phone must be paired with Developer Mode enabled. macOS notarization and App Store distribution validation remain separate from this development installation.

## Release polish validation

The implementation covers save/resume; replay camera offsets; short landscape framing; pause/reduced motion; export presets; running limbs and moving selection rings; facing-aware ball contact and kick timing; shoulder/crane composition; scenery fades; continuous distance-based replay spin; shorter dice and skippable entrances; batched scenery and reused meshes; cleaner limbs and kit trim; contextual move guidance; keyboard board control; menu contrast; native CI/regression checks; audio/mute; immediate rematches; and distinct shirt numbers/solo outcomes.

Local checks passed across the native suites (including 727 rule transitions and three full computer matches), rendered UI at four viewport sizes, and the full entrance journey. The exported macOS app passed headless and rendered startup checks and signature verification; its resource pack excludes editor tools and tests and includes the license notices. Xcode built the iOS project both unsigned and with Apple Development signing for team 9833XCBZ6Q. The signed build installed successfully on the paired iPhone 17 Pro (aPhone). The camera-control update was installed and its running process verified on that phone; sustained device performance and physical swipe feel remain untested. Windows execution and the remote CI run have not been verified here.

On the development Apple M3 at 1280×800 with the Mobile renderer, the rendered performance check measured gameplay at 704 median draw calls (previous short audit approximately 1,209) and the home screen at 125 (previous approximately 346). Gameplay median frame interval was 16.65 ms, p95 17.27 ms, and maximum 21.1 ms in the short sample. The entrance still had a first-use frame near 40 ms; steady entrance p95 was 17.3 ms. These are short local samples, not sustained device or thermal guarantees. The dice viewport now shares the main viewport's MSAA setting to avoid a second pipeline variant.

A four-game local comparison against the previous AI produced four wins for the new version, across both teams (6–0 aggregate goals). This is a small smoke benchmark, not a strength rating. Its longest observed search slice was 7.34 ms on the development Mac; phone thinking time still needs playtesting.

Before public release, run sustained matches on target iPhones and Windows hardware, check touch/audio/safe-area behavior on devices, and complete Apple signing/notarization and store validation. No store upload is part of this change.
