# Changelog

## [HEAD] Refine debug editor placement/repeat and move crafting panel above inventory
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
