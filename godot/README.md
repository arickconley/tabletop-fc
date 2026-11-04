# Tabletop FC — Godot

First native playable version, alongside the web game. Open `project.godot` in **Godot 4.7.2** and press **F5**. The project uses GDScript and the Mobile renderer.

## Play

Two people share the screen. Tap the 3D dice floating over the pitch to start the kickoff (reroll if tied). Every normal turn opens with a central die: tap it, watch it tumble and settle on the result, then shrink beside the moves counter. The counter includes any free kick step. Eligible players have pulsing team-colored rings.

The main HUD uses floating text and underlined actions instead of boxed panels. The dice have beveled meshes and pips on all six faces, including the small die beside the counter. Their animation settles on the value chosen by the match rules; it does not use physics to determine the roll.

Choose a highlighted player and tap outlined squares to run. Contact with the ball starts kick planning: select squares one at a time along the numbered arrows, then press **Confirm kick**. The ball rolls along the route and the next player's dice prompt appears automatically. A legal route can finish early with moves left; kickoffs still require their exact distance. Passes must continue off the receiver, and required goal-mouth relocation is previewed before confirmation.

**Undo** revises the current turn: it undoes a pending relocation, removes the last draft square, or undoes a run. Confirmation ends the turn and clears undo history. If you only run, **End turn** remains available when the position is legal. Players hop when moving, breathe and sway, and lean into kicks. Board input is locked during dice and ball animations.

The **...** menu has an overhead camera, rules, and restart confirmation. Portrait view turns the pitch lengthways to make squares easier to tap. The HUD accounts for mobile safe areas and device scale. There is no movement pad.

Included rules: the default formation, opening and halftime kickoffs, orthogonal running, free kick steps, passing, one 45° bend per kick, goal-mouth relocation, defensive-box and opponent-path checks, goals and restarts, 20 rolls each, halftime, draws, and undo.

The miniature stadium includes rounded footballers with faces, varied hair and skin tones, numbered kits, boots, striped turf, goal nets, corner flags, tiered bleachers, spectators, railings, and floodlights. Foreground stands and towers hide with the camera to keep the pitch clear; portrait framing prioritizes playable squares over fitting all the scenery. Models are generated locally, with shared materials and batched spectators; no downloaded model packs are required.

This milestone is **local two-player only**. Closing the game loses the current match. AI, persistence, manual formations, and web-save transfer are not implemented yet.

## Code

- `scripts/rules.gd`: rendering-independent port of `../src/game.js`. Transitions return a new state or `{ "error": message }`; callers must handle errors.
- `scripts/board.gd`: procedural pitch, movement animation, route previews, legal-square markers, picking, and camera fitting.
- `scripts/footballer.gd`: toy-style player models and their collision bodies.
- `scripts/stadium.gd`: bleachers, batched crowd, floodlights, and camera-dependent scenery visibility.
- `scripts/match.gd`: native touch/mouse input, kick drafts and confirmation, compact HUD, turn actions, undo, and menus.
- `scripts/turn_dice.gd`: tappable dice, result reveal, and the animation into the moves strip.
- `scripts/die.gd`: lit 3D dice, face orientation, tumbling, and transparent rendering for the prompt and counter.
- `scenes/match.tscn`: startup scene. Geometry and HUD are built at runtime.
- `assets/fonts`: Barlow Condensed, with its SIL Open Font License.

The installed MCP Toolkit addon belongs to the editor integration. Its bridge is `@npgamedev/godot-mcp-server@1.1.2`, not the separate `godot-ai` server. Point `GODOT_MCP_PROJECT_PATH` at this folder when the client starts from the parent repository.

## Checks

From the repository root (replace `godot` below with your Godot executable):

```sh
node godot/tests/reference.mjs
godot --headless --path godot --script tests/rules_check.gd
godot --path godot --script tests/scene_check.gd
godot --path godot --script tests/layout_check.gd
```

The rule check compares 727 transitions and their legal targets against the existing JavaScript game, including complete matches. The native scene check covers central dice, ties, docking, compact layout, eligible players, movement, draft isolation, bends, passes, scoring, kickoff distance, relocation, automatic handoff, input locking, undo boundaries, halftime, and full time. No browser or Playwright is involved.

## Native distribution next

Install the matching **4.7.2 export templates** through Editor → Manage Export Templates. Then add iOS, macOS, and Windows Desktop presets under Project → Export.

- **iOS:** configure your bundle identifier and Apple team, export the Xcode project, then sign and build in Xcode. Test on an actual iPhone. The iOS simulator requires the Compatibility renderer.
- **macOS:** export an app; public distribution needs the appropriate signing and notarization.
- **Windows:** export an x86_64 executable with its game data.

Export templates and signing credentials are not included. No distribution builds have been produced yet.
