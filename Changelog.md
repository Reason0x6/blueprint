# Changelog

## [HEAD] Drag-out inventory drop to world
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
