# Tabletop FC — Godot

First native playable version, alongside the web game. Open `project.godot` in **Godot 4.7.2** and press **F5**. The project uses GDScript and the Mobile renderer.

## Play

The main menu uses the web edition’s **TABLE / TOP FC** styling over an empty stadium, with a groundskeeper wandering the pitch behind a mower. Choose **Play Game** and the camera descends into the stadium’s locker room. Customize your team with **12 colours** and **Plain, Stripes, or Hoops** shirts on the player standing in the room, then choose **Vs computer** or **2 players**.

**Confirm kit** follows that same player through the tunnel onto the pitch. A perspective camera travels just behind the captain's shoulder at player height, with a fixed lens while walking. After clearing the tunnel it physically rises and pulls back into the gameplay view. Teammates run into formation; only then do the kickoff dice appear. The opponent receives a random contrasting colour. Foreground locker-room and tunnel geometry fades out as the camera rises so it cannot obscure the pitch. Colours carry through the models, bases, highlights, dice, score labels, and turn prompts. Kit choices remain selected for the current app session.

Tap the 3D dice floating over the pitch to start the kickoff (reroll if tied). Every human turn opens with a central die: tap it, watch it tumble and settle on the result, then shrink beside the moves counter. The computer rolls and plays its own turns automatically, showing its route before the ball moves. The counter includes any free kick step. Eligible players have pulsing team-colored rings.

The main HUD uses floating text and compact action buttons instead of boxed panels. Confirm kick has a solid lime background with dark text so it stays readable over the pitch. The dice have beveled meshes and pips on all six faces, including the small die beside the counter. Their animation settles on the value chosen by the match rules; it does not use physics to determine the roll.

Choose a highlighted player and tap outlined squares to run. Contact with the ball starts kick planning: select squares one at a time along the numbered arrows. Tap the current endpoint again to reveal **Confirm kick** beside it, then press the button to play the route. The button stays inside the screen edges and disappears when you edit the path. A legal route can finish early with moves left; kickoffs still require their exact distance. Passes must continue off the receiver, and required goal-mouth relocation is previewed before confirmation. The next player's dice appear when the ball finishes moving.

Tap an earlier path square to rewind directly to it, restoring moves and removing the later route. Tap the ball's starting square to clear the kick draft. Earlier run squares also rewind the player, and tapping a relocated player's previous square revises that relocation. There is no Undo button. Confirmation ends the turn and clears its history. If you only run, **End turn** remains available when the position is legal. Players hop when moving, breathe and sway, and lean into kicks. Board input is locked during dice and ball animations.

The **...** menu has an overhead camera, rules, and restart confirmation. Camera switches and resizing ease into the new view, and the confirmation button follows its square throughout. Portrait view turns the pitch lengthways to make squares easier to tap. The HUD accounts for mobile safe areas and device scale, with a fixed feedback allowance so messages appearing or disappearing never reframe the pitch. There is no movement pad.

Included rules: the default formation, opening and halftime kickoffs, orthogonal running, free kick steps, passing, one 45° bend per kick, goal-mouth relocation, defensive-box and opponent-path checks, goals and restarts, 20 rolls each, halftime, draws, and undo.

The miniature stadium includes rounded footballers with faces, varied hair and skin tones, numbered kits, boots, striped turf, goal nets, corner flags, tiered bleachers, spectators, railings, and floodlights. Foreground stands and towers hide with the camera to keep the pitch clear; portrait framing prioritizes playable squares over fitting all the scenery. Models are generated locally, with shared materials and batched spectators; no downloaded model packs are required.

The computer works offline and uses the same rules and dice as the human. Its bounded search prefers scoring, territory, possession, and keeping its keeper home; it runs in small slices between frames. There is one difficulty level. Closing the game loses the current match. Persistence, manual formations, and web-save transfer are not implemented yet.

## Code

- `scripts/rules.gd`: rendering-independent port of `../src/game.js`. Transitions return a new state or `{ "error": message }`; callers must handle errors.
- `scripts/computer.gd`: incremental port of `../src/ai.js`; searches complete legal turns without changing the live match.
- `scripts/team_lobby.gd`: web-style main menu, locker-room kit controls, and game mode selection.
- `scripts/stadium_journey.gd`: physical locker room and tunnel, groundskeeper, camera travel, and the customized player's entrance into the match.
- `scripts/menu_backdrop.gdshader`: directional menu shading that leaves the stadium and locker-room player visible.
- `scripts/team_kits.gd`: named palette, shirt designs, and contrasting opponent selection. Internal blue/red rule IDs stay independent of appearance.
- `scripts/board.gd`: procedural pitch, movement animation, route previews, legal-square markers, picking, and camera fitting.
- `scripts/footballer.gd`: toy-style player models and their collision bodies.
- `scripts/stadium.gd`: bleachers, batched crowd, floodlights, and camera-dependent scenery visibility.
- `scripts/match.gd`: native touch/mouse input, kick drafts and confirmation, compact HUD, turn actions, undo, and menus.
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

From the repository root (replace `godot` below with your Godot executable):

```sh
node godot/tests/reference.mjs
godot --headless --path godot --script tests/rules_check.gd
godot --path godot --script tests/scene_check.gd
godot --path godot --script tests/layout_check.gd
godot --headless --path godot --script tests/computer_check.gd
godot --path godot --script tests/computer_scene_check.gd
godot --path godot --script tests/lobby_check.gd
```

The rule check compares 727 transitions and their legal targets against the existing JavaScript game, including complete matches. The native scene check covers central dice, ties, docking, compact layout, eligible players, movement, draft isolation, bends, passes, scoring, kickoff distance, relocation, automatic handoff, input locking, undo boundaries, halftime, and full time. No browser or Playwright is involved.

The computer checks cover both kickoff teams at every distance, scoring passes, required relocation, blocked shots, impossible routes, and three seeded full matches. The computer scene check covers mode selection, automatic rolls, animated playback, human input locking and handoff, halftime, cancellation, and local play.

The lobby check covers the empty pitch and moving groundskeeper, camera descent, all kit colours and designs, responsive controls, the same player traversing the tunnel, the camera handoff, final formation, input locking, colour propagation, and returning to the menu.

## Native distribution next

Install the matching **4.7.2 export templates** through Editor → Manage Export Templates. Then add iOS, macOS, and Windows Desktop presets under Project → Export.

- **iOS:** configure your bundle identifier and Apple team, export the Xcode project, then sign and build in Xcode. Test on an actual iPhone. The iOS simulator requires the Compatibility renderer.
- **macOS:** export an app; public distribution needs the appropriate signing and notarization.
- **Windows:** export an x86_64 executable with its game data.

Export templates and signing credentials are not included. No distribution builds have been produced yet.
