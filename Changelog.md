# Changelog

## [HEAD] Double entity durability regeneration speed
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
