# Changelog

## [HEAD] Unreleased
- Player movement now checks full player-hitbox occupancy before applying WASD or click-to-move steps, so structure water collision blocks movement immediately instead of only reverting after overlap.
- Added shared player auto-move cancel handling when movement is blocked by water/entity hitboxes.
- Added configurable terrain block hitboxes by block index via `setup_terrain_block_hitboxes`/`set_terrain_block_hitbox`, with block `11` explicitly non-blocking.
- Wired terrain block hitbox collision into both point checks and full player-hitbox movement checks, and added debug rendering for configured terrain block collision boxes when hitbox debug is enabled.
- Added configurable water collision oversize (`WATER_COLLISION_OVERSIZE_PX`) and updated water blocking checks to test neighboring water tiles so expanded water hitboxes work correctly across tile edges.
- Fixed terrain block hitbox queries to include neighboring tiles for both point and rect checks, so offset/oversized hitboxes are respected consistently for structure tiles too.
- Hitbox debug rendering (entity, water, terrain-block outlines) now draws on the pause-menu layer while paused, so toggling hitboxes in the pause menu shows them immediately above the gray overlay.
- Water debug hitboxes now visualize the actual per-pixel `water.png` collision mask (with oversize margin) instead of a full-tile blue outline, so structure-water debug matches real collision shape.
- Grid debug is now OFF by default at startup (still toggleable from the pause menu).
- Fixed hitbox-toggle crashes by replacing per-pixel-per-tile water debug fills with lightweight per-tile mask-bounds debug rectangles.
- Fixed water collision mask dimension loading to use the actual decoded `water.png` width/height (removed erroneous `+14` sizing), keeping collision sampling and debug bounds in sync.
- Terrain block collision now supports multiple hitboxes per block index via `add_terrain_block_hitbox`, while `set_terrain_block_hitbox` remains as a clear-and-set helper for single-box cases.
- Updated terrain block point, rect, and debug collision paths to evaluate/draw all configured hitboxes for the block tile instead of only one.
- Synced all currently pending workspace changes (code, terrain data, and image/tileset asset updates) into a single commit.
- Terrain structure tokens now support water variants: `water_1..water_4`, with numeric aliases `0 -> water_1`, `-1 -> water_2`, `-2 -> water_3`, `-3 -> water_4`.
- Water terrain rendering now selects per-tile variant sprites, and water collision/debug mask logic now reads per-variant masks (`water_1.png..water_4.png`) with fallback to variant 1/legacy `water.png`.

## [bdfe590] Fix water collision sampling step type to f32 so the game builds successfully
- Fixed Odin type mismatch in water collision hitbox sampling by making the loop `step` explicitly `f32`, resolving build errors at `x += step` / `y += step`.

## [aed2934] Add active pause menu overlay with global ESC open/close behavior
- Added a pause menu overlay (`UI_OVERLAY_PAUSE`) with centered Resume UI.
- Added a full-screen gray dimmer layer behind the pause panel to separate menu UI from gameplay.
- Moved debug toggles (hitboxes, overlap, durability) from always-on top-left HUD into the pause menu.
- Fixed pause-menu debug button label sizing/alignment so text stays inside the button bounds.
- Added a new pause-menu `Grid: ON/OFF` debug toggle and gated world-grid rendering behind it (defaults ON).
- Fixed pause-menu button label anchoring to use rect centers so labels no longer render left-shifted/outside buttons.
- Replaced global `bg_use_forest_grass` map-wide texture choice with deterministic per-tile forest-grass overlays, so background tiles now mix default and forest variants in-world.
- Fixed a compile error in forest-grass tile hashing by replacing invalid `^=` usage with Odin-compatible XOR expression syntax.
- Changed mixed forest tile draws to the base world layer submission path so they render as background behind gameplay visuals.
- Increased player movement speed slightly from `100` to `112`.
- Added a faint place-range circle around the player while a placeable item is equipped, showing max placement distance.
- Added chunked biome background rendering with deterministic `64x64` tile chunks and four biome types: Desert, Plains, Forest, and Ruins.
- Added biome tile sprite hooks (`desert_bg_tile`, `plains_bg_tile`, `forest_bg_tile`, `ruins_bg_tile`) with per-biome fallback solid-color tiles when biome textures are missing.
- Added a new animated `grass_ent` entity type using `grass.png` and chunk-based deterministic world spawning so grass appears randomly across all biomes as you explore.
- Added deterministic chunk vegetation generation for trees in Plains and Forest biomes so those chunks spawn random tree entities.
- Fixed biome/vegetation chunk math to use world grid tile size (`ENTITY_GRID_SIZE`) instead of background texture pixel size, so grass/trees now spawn visibly in nearby chunks.
- Added per-tile biome background variation selection with deterministic hashing so backgrounds can mix multiple textures instead of repeating a single tile.
- Wired Plains biome test variants (`Plains_0..4`) into biome background selection, with automatic fallback to the single biome tile or fallback color if variants are unavailable.
- Reworked biome background selection to stop using `Plains_0..4` and instead mix base biome textures procedurally from a smaller shared texture set per biome.
- Added Plains autotile terrain rendering from `tilemap_color1.png` using neighbor-mask tile selection (edges/corners/center) to reduce visible repetition.
- Added `res/images/tilemap_color1.png` import path support (optional sprite load) and UV cell slicing (`32px` cells) for drawing autotile cells into world grid tiles.
- Removed biome-driven terrain selection in favor of a single procedural terrain-mask generator for basic world generation.
- Terrain rendering now uses only `res/tileset/Tilemap_color1.png` (loaded via `tilemap_color1` sprite override path) with neighbor-based autotile edge/corner/center selection.
- Grass and tree chunk spawns now use the same terrain mask check (instead of biome checks), so vegetation populates generated land tiles consistently.
- Terrain tileset sampling now uses `64x64` block indices (`1..54`) from `Tilemap_color1`, with a dedicated `terrain_block_index_for_tile` selector hook for future per-tile block rules.
- Default terrain generation currently fills with block `11` (flat ground), as requested, while keeping the block-selector path ready for later edge/water block mapping.
- Updated terrain block selection to step through `1 -> 2 -> ... -> 54` in-order across tiles (wrapping) for block-map validation.
- Added centered per-tile block index labels so each rendered tile shows the block number currently used.
- Corrected tileset block row indexing so block `1` maps to the top-left block of the `9x6` tilemap layout.
- Set terrain block selector back to a constant fill of block `11` for full-map flat-ground tiling.
- Changed grid-snapped entity placement to snap to tile centers (`+ grid*0.5`) instead of tile edges.
- Terrain block-number labels now render only when grid debug is enabled (`Grid: ON`).
- Fixed center-grid snapping drift by snapping relative to half-tile offset (`snap(pos-half)+half`) so snapped entities stay stable instead of translating each frame.
- Aligned placeable preview and placement target snapping to tile centers so preview location matches actual placed entity location.
- Locked placeable preview to `pending_place_pos` while the player is auto-moving to place, preventing camera/mouse world-space drift from making the target appear to move.
- Switched center-grid snapping to floor-cell center mapping (`floor(v/grid)*grid + half`) to eliminate consistent one-tile vertical offset during placement.
- Tree destruction now always spawns a `sprout_ent` in addition to existing wood break drops, guaranteeing wood + sprout outcome on tree break.
- Refactored entity break drops from single `break_drop_item/count` fields to a multi-drop list (`break_drops + break_drop_len`) so an entity can define more than one guaranteed item drop on break.
- Added data-driven terrain structure loading from `res/data/terrain_structures.txt` using syntax like `name = [[...],[...]]`, where each array position maps directly to tile column/row.
- Added terrain structure tokens for numeric block indices (`1..54`) and `water`, with `water` tiles rendering `water.png`.
- Terrain structures can now be manually spawned in code via `spawn_terrain_structure(name, world_pos)`/`spawn_terrain_structure_at_tile`, with a startup example spawn wired for `island_1`.
- Terrain tile resolution now uses spawned structure instances (last-spawned wins on overlap), with block `11` fallback for unoccupied tiles.
- Terrain rendering now draws a water underlay beneath non-water tiles so transparent pixels in terrain block sprites reveal water below.
- Terrain structure parser now accepts quoted tokens (e.g. `"water"`), and structure spawning now accepts numeric ids (`"1"` = first loaded structure) in addition to structure names.
- Structure tile indexing now maps arrays as top-to-bottom and left-to-right from the structure origin (`row 0` is top row).
- Terrain structure token parsing now accepts `0` as water in addition to `water`/`"water"`.
- Added texture-accurate water collision: `water.png` alpha is loaded as a collision mask and player blocking now samples water pixels in world space (including path target checks and post-move hitbox rejection).
- Water collision debug now renders visible tile outlines for terrain `water` tiles when hitbox debug is enabled, including structure-spawned water tiles.
- Increased water collision sampling precision to per-pixel (`1px`) across actor hitbox tests so thin water-mask regions no longer miss blocking.
- `Esc` now opens pause when no overlays are open, and closes all overlays when any overlay is open.
- Game update is now actively paused while pause overlay is open (world systems stop updating).
- Overlay input handling is now centralized in `game_update` instead of inventory-only escape handling.

## [adafee3] Add modal UI overlay gating plus sapling placement, break bonus drops, and visible large grid
- Added generic UI overlay gating (`is_any_ui_overlay_open`) so movement, hitting, right-click use, and interaction pause while any overlay is open, plus `Esc` close-all overlay behavior.
- Added `sapling` as an item kind and placement flow: with sapling equipped, clicking empty valid world space now makes the player move into range and then place a `sapling_ent`.
- Added low-opacity placeable hover preview for equipped placeables, visible within `2x` interaction range.
- Breaking `tree_ent`, `sapling_ent`, and `sprout_ent` now drops their configured break drops plus a random `0..1` bonus sapling item.
- Increased world entity grid size and added world grid rendering so the larger placement grid is visible.
- Increased floating pickup item draw scale slightly.
- Fixed `UI_OVERLAY_INVENTORY` constant declaration syntax.

## [13c610c] Merge crafting output into matching held stack on left click
- Left-clicking crafting output while already holding the same item now consumes ingredients and adds crafted output directly into the held stack.
- Merge path respects max stack capacity and only crafts when the full output stack can fit.

## [14d5c09] Scale tree wood drop chance by held-item durability multiplier
- Updated tree `on_hit` drop logic to multiply `TREE_WOOD_HIT_DROP_CHANCE` by the hitter's `item_hit_durability_multiplier`.
- Tree wood drop chance now scales with equipped item effectiveness (including zero-chance items).

## [049606f] Use target-side left/right swing facing on hits and facing-based swings on empty clicks
- Entity-hit swings now face only left/right based on whether the hit target is on the left or right of the player (no arbitrary angle direction).
- Empty-space click swings continue to use the player's current facing direction.
- Swing visuals remain offset away from the character face.
- Fixed click-flow override where a fallback facing swing could replace target-side hit swing orientation in the same click.

## [36c1c8b] Map stone multitool swings to stone_multitool_swing animation
- Added `stone_multitool_swing` to `Sprite_Name`/`sprite_data` and mapped `item_swing_sprite(.stone_multitool)` to that sprite.
- Player hit swings now use `stone_multitool_swing.png` (with its meta-driven animation frames) when a stone multitool is equipped.

## [9379dd0] Add player item swing FX that points at melee hit targets
- Added a player swing FX state and animation playback that triggers when the player hits an entity.
- Swing visuals rotate toward the hit target direction and render from the player hand position.
- Added item swing sprite selection helper (currently falls back to the item icon sprite until dedicated `<item>_swing` sprite enums are wired).

## [a086547] Reduce equipped item label size by 60 percent
- Set the hotbar `Equipped:` UI label draw scale to `0.4`, making it 60% smaller than the previous default size.

## [0a57857] Randomize repeating background texture and remove player tint filter
- Added `forest_grass_texture` sprite support and random startup selection between `bg_repeat_tex0` and `forest_grass_texture`.
- Background repeat UV assignment now uses the randomly selected sprite for the session.
- Tuned forest grass selection chance to roughly `1 in 3` sessions.
- Removed the player update-time `scratch.col_override` blue tint so the player texture now renders without that color filter.

## [3b7fd54] Normalize player run facing to match idle orientation
- Added a run-sprite specific flip correction so `player_run` faces the same direction as `player_idle`.

## [b19153c] Suppress hit highlight for zero-damage hits
- `get_hit_durability_damage` now permits `0` damage results from held-item multipliers.
- `entity_apply_hit` now only applies the white hit highlight when computed damage is greater than `0`.

## [b4321c9] Simplify durability multiplier config to only non-default items
- Simplified `item_hit_durability_multiplier` so only items with non-`1.0` values are explicitly listed.
- All unspecified items now use the default multiplier path (`1.0`).

## [f293f6f] Scale durability damage per hit by held item multiplier
- Added `item_hit_durability_multiplier` and applied it in `entity_apply_hit` so held items now scale how much durability each hit removes.
- Hit damage now resolves from the player's equipped item and applies integer durability loss via multiplier-based damage.

## [cfc8421] Boost hit flash effect when durability is below 3
- Increased white hit-flash intensity and outline thickness for low-durability entities (`durability < 3`).
- Slowed hit-flash fade-out at low durability so the stronger effect is visible longer.
- Further increased low-durability flash strength with a higher alpha multiplier, slower decay, and added diagonal outline passes.

## [cb1807b] Speed up durability regeneration and shorten regen delay
- Increased durability regeneration rate from `1.0` to `2.0` per second.
- Reduced post-hit regeneration delay from `1.0s` to `0.5s` so regen starts sooner.

## [63f4468] Move hit-drop spawns closer to player with hitbox-edge clamp
- Hit-triggered drops now spawn halfway between player and entity, then clamp to a maximum of `40px` from the closest point on the entity hitbox edge.
- Updated tree on-hit wood drops and durability break drops to use the new midpoint + edge-clamp spawn position before bounce motion.

## [1ecaca1] Add item-based hit cooldown UI/hold gating and white hit flash outline
- Added item-based hit cooldown attributes via `item_hit_cooldown`, and now left-click usage starts cooldown from the currently equipped item.
- Holding left mouse now only applies repeat hits when cooldown is finished, instead of using a fixed repeat timer.
- Added a world-space cooldown bar under the player showing remaining hit cooldown after click/use.
- Added per-hit white flash outline rendering on hit entities with timed fade-out.

## [c78b49c] Fix hit-drop bounce by excluding item pickups from grid snapping
- Removed `item_pickup` from grid snap targets so bounced drops keep their velocity-based movement toward the player.
- Fixes tree wood on-hit drops appearing static instead of traveling toward the player.

## [6d74ea5] Add stone blade/multitool textures and bounce hit-drops toward player
- Added sprite support for `stone_blade.png` and `stone_multitool.png`, and mapped `stone_blade` / `stone_multitool` item icons to those textures.
- Added `spawn_item_pickup_towards_player` for entity hit drops so dropped items get initial velocity toward the player and a short pickup delay.
- Updated tree on-hit wood drops and durability break drops to use the bounce-to-player drop path.

## [cfd84ec] Add hold-to-hit durability cycling at 0.6-second intervals
- Added left-mouse hold hit cycling so holding on an entity repeats durability hits every `0.6s`, matching repeated click cadence.
- Hold cycling locks to the entity initially hit, stops when the mouse leaves that entity, and clears on mouse release.
- Added safeguards so world hold-hit cycling is disabled while the inventory UI is open.

## [4522331] Double entity durability regeneration speed
- Increased durability regeneration rate from `0.5` to `1.0` durability per second while keeping the 1-second post-hit delay.

## [2970ee5] Add delayed durability regeneration for entities after hits
- Added per-entity durability regeneration state (`durability_max`, `last_hit_time`, regen accumulator) and per-frame regen updates.
- Entities now wait 1 second after being hit before regenerating missing durability gradually over time.
- Added setup helper wiring so durability/max values remain setup-defined while supporting regeneration behavior.

## [c1891a1] Add debug toggle to render entity durability above world entities
- Added a third top-left debug button (`Durability: ON/OFF`) to toggle durability labels at runtime.
- Added world debug rendering that displays current durability above entities that have durability values.

## [a51e3da] Add per-entity hit durability with tree on-hit wood drops and break drops
- Added per-entity `durability`, `on_hit_proc`, and break-drop (`break_drop_item`, `break_drop_count`) fields to `Entity`, with values configured in each `setup_*` proc.
- Added left-click world hit handling that applies entity hits, reduces durability by 1 per click, and destroys entities at 0 durability while dropping their configured break item.
- Added tree-specific `on_hit_proc` that spawns `wood` with a 15% chance on each hit.

## [c8504b4] Add stone_multitool item support so existing recipe resolves
- Added `stone_multitool` to `Item_Kind` and token parsing so `stone_multitool:1` outputs in `crafting_recipes.txt` load correctly.
- Added inventory/UI mappings (`item_name`, `item_icon_sprite`, `item_max_stack`) for the new item, using a stack size of `1`.

## [3b72a9a] Convert crafting to shape-based 2x3 slot recipes
- Replaced crafting recipe matching logic so recipes now match exact slot layout on the 2x3 crafting grid instead of aggregated item counts.
- Updated crafting ingredient consumption to consume from the exact matched slots defined by each recipe pattern.
- Switched `res/data/crafting_recipes.txt` to a shape format: `r0c0,r0c1 | r1c0,r1c1 | r2c0,r2c1 -> output`, with `_`/`.`/`empty` as empty-cell tokens.

## [c52166d] Enable player collision for sprout entities
- Changed `setup_sprout_ent` so `sprout_ent` now sets `blocks_player = true`, making sprouts collide with and block player movement.

## [bae4fc8] Map stone and rope items to their new texture sprites
- Added `stone` and `rope` sprite ids in `Sprite_Name`/`sprite_data` so they load from `res/images/stone.png` and `res/images/rope.png`.
- Updated `item_icon_sprite` to return `.stone` for `Item_Kind.stone` and `.rope` for `Item_Kind.rope` instead of placeholder sprites.

## [ee236a6] Fix startup crash by matching item sprite names to texture filenames
- Renamed item sprite enum entries from `wood_item`/`sticks_item`/`fibre_item` to `wood`/`sticks`/`fibre` so atlas loading matches `res/images/wood.png`, `sticks.png`, and `fibre.png`.
- Updated `sprite_data` and `item_icon_sprite` mappings to the renamed sprite ids, removing the missing-file assert on startup.

## [eefeaed] Add sapling/sprout world entities and item-only resource textures
- Added `sapling_ent` and `sprout_ent` setups with startup world spawns so both can be placed/tested as standalone entities.
- Added explicit hitbox definitions for sapling and sprout entity kinds, with saplings blocking player movement and sprouts remaining non-blocking.
- Updated resource item icon mapping so `wood`, `stick`, and `fiber` now use `wood_item`, `sticks_item`, and `fibre_item` textures instead of placeholder sprites.

## [8fb4623] Merge same-item stacks on left-click placement
- Updated held-item left-click placement so clicking a slot with the same item now merges into that slot instead of swapping.
- Merge respects max stack size and keeps any overflow in the held stack.
- Preserves existing left-click swap behavior for different item types.

## [5c8b947] Switch inventory interaction to held-item click placement
- Changed inventory/crafting interaction to click-to-hold semantics instead of drag-release semantics.
- Left click on a slot now places the held stack and swaps with any existing stack in that slot.
- Right click on a slot now places exactly one held item when the slot is empty or has the same item.
- Closing the inventory while holding items now drops the held stack into the world automatically.

## [83823cb] Add data-driven crafting recipe file format and loader
- Added a simple editable recipe file at `res/data/crafting_recipes.txt` using `input_item:count + input_item:count -> output_item:count` syntax.
- Replaced hardcoded crafting recipe matching/consumption with generic runtime recipes loaded from the file at startup.
- Added parser helpers, token-to-item mapping, and default fallback recipes when the file is missing or invalid.

## [71af3c6] Add rounded-corner hitbox collision and grid-snapped entity constraints
- Added rounded-corner (corner-cut) hitbox collision helpers and switched player/blocker and projectile/blocker checks to use the rounded collision path.
- Added rounded point-block checks for click-to-move target validation so pathing respects rounded hitbox corners.
- Added a grid snap pass for entities (excluding player/projectiles/indicator FX) so world entities are constrained to a consistent grid.
- Included current asset workspace changes, including `Sapling.png` and `Sapling.meta`, in this commit.

## [abe9a53] Remove shift-right-click box editor/debug UI
- Removed the shift-right-click entity box editor workflow and all related debug panel UI.
- Removed live hitbox/overlap override paths and restored `get_entity_hitbox_rect` / `get_entity_overlap_rect` to code-defined behavior only.
- Restored normal right-click movement handling without the editor-selection branch.

## [255c5ab] Make debug code output compact and selectable
- Replaced long full-line code text in the debug editor with compact selectable rows for hitbox and overlap code.
- Added click-to-select + click-to-copy behavior for each code row using system clipboard integration.
- Added selection status text and kept the panel compact while preserving generated code snippets.

## [526e8fe] Refine debug editor placement/repeat and move crafting panel above inventory
- Moved and compacted the hitbox/overlap debug editor into the top-left so it no longer extends off-screen.
- Added press-and-hold behavior for debug +/- controls using frame-based repeat while left mouse is held.
- Made the crafting panel wider and positioned it above the inventory panel, with updated slot anchors in the new layout.

## [1278890] Add shift-right-click hitbox/overlap debug editor UI
- Added a debug box editor that opens for a selected entity when you Shift+Right-click it, with live selection clear on empty-space Shift+Right-click.
- Added on-screen +/- controls for hitbox and overlap offset/size values and applied those overrides live to collision/overlap queries for the selected entity.
- Added copy-ready code suggestion lines in the debug panel to help transfer edited values back into `get_entity_hitbox_rect` and `sprite_data`.

## [db85ebf] Split inventory and crafting into separate UI panels
- Separated the combined inventory/crafting layout into two distinct boxes with independent panel rects.
- Kept existing drag/drop behavior and slot hit-testing intact by reusing the same slot helper procs with updated panel anchors.
- Updated panel headers so inventory and crafting each have clear labels in their own boxes.

## [b184fe2] Add tree entity using Tree texture
- Added a new `tree_ent` entity kind and `tree` sprite entry mapped to `Tree.png`, with tree-specific setup and draw behavior.
- Added a trunk-focused blocking hitbox for trees so canopy overlap still works while the trunk blocks movement.
- Spawned a tree instance at game start for immediate in-world testing.

## [98fea29] Add baseline crafting items, recipes, and crafting UI
- Added foundational crafting materials and intermediates (`wood`, `stone`, `fiber`, `stick`, `rope`, `stone_blade`) and seeded starter pickups in the world.
- Implemented crafting state with a 2x3 crafting input grid plus a single output slot, integrated into the inventory panel UI.
- Added recipe evaluation/ingredient consumption and drag-and-drop support between inventory/hotbar and crafting slots, with crafted output pickup via click.

## [b47dae9] Use dagger_item_flying for thrown dagger animation/meta
- Added `dagger_item_flying` to the sprite enum/data so runtime meta loading can pick up `res/images/dagger_item_flying.meta`.
- Switched dagger projectile rendering from `dagger_item_thrown` to `dagger_item_flying`.
- Included the new `dagger_item_flying.png/.meta` assets in source control.

## [2081454] Drop inventory throws just outside auto-pickup radius
- Changed drag-out inventory drops to spawn just outside the player's auto-pickup area instead of exactly at mouse world position.
- Added shared pickup/drop radius constants and aligned auto-pickup range checks to use them.
- Uses mouse direction from the player to choose the drop side, with facing-direction fallback when cursor direction is degenerate.

## [a2f99c1] Drag-out inventory drop to world
- Added world-space mouse position conversion so UI drag/drop can spawn entities in world coordinates.
- When a dragged inventory stack is released outside valid inventory/hotbar slots, it now spawns an item pickup in the world at the cursor position.
- Preserved existing slot drop behavior (swap/stack/move) when released over valid slots.

## [fe3730b] Right-click close-range detour around blockers
- Added right-click path detour behavior that inserts an intermediate waypoint when the player starts within 10px of a blocking hitbox.
- Applied detours for both empty-ground clicks and entity clicks, then automatically resumes to the final target.
- Cleared queued detour targets when WASD movement takes control or collision-stop cancels click movement.

## [4e99446] Changelog format bootstrap
- Added this changelog file and established commit-linked heading format for future entries.
- Future entries will use `[HEAD]` for current uncommitted changes and then be finalized to `[<short-hash>]` after commit.

## [22a3ac5] Changes galore
- Legacy commit heading backfilled with short hash to match the new changelog heading format.
