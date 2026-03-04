#+feature dynamic-literals
#+feature using-stmt
package main

/*

GAMEPLAY O'CLOCK MEGAFILE

*/

import "utils"
import "utils/shape"
import "utils/color"

import "core:log"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import stbi "vendor:stb/image"

import spall "core:prof/spall"

VERSION :string: "v0.0.0"
WINDOW_TITLE :: "Template [bald]"
GAME_RES_WIDTH :: 480
GAME_RES_HEIGHT :: 270
window_w := 1280
window_h := 720

when NOT_RELEASE {
	// can edit stuff in here to be whatever for testing
	PROFILE :: false
} else {
	// then this makes sure we've got the right settings for release
	PROFILE :: false
}

//
// epic game state

Game_State :: struct {
	ticks: u64,
	game_time_elapsed: f64,
	cam_pos: Vec2, // this is used by the renderer

	// entity system
	entity_top_count: int,
	latest_entity_id: int,
	entities: [MAX_ENTITIES]Entity,
	entity_free_list: [dynamic]int,

	// sloppy state dump
	player_handle: Entity_Handle,
	debug_show_hitboxes: bool,
	debug_show_overlap_boxes: bool,
	debug_show_durability: bool,
	debug_show_growth: bool,
	debug_show_grid: bool,
	hold_hit_target: Entity_Handle,
	has_hold_hit_target: bool,
	hit_cooldown_end_time: f64,
	hit_cooldown_duration: f64,
	ui_overlay_mask: u32,
	swing_active: bool,
	swing_sprite: Sprite_Name,
	swing_anim_index: int,
	swing_next_frame_end_time: f64,
	swing_rotation: f32,
	swing_dir: Vec2,
	inventory: Inventory_State,
	spawned_vegetation_chunks: [dynamic]u64,
	terrain_structure_instances: [dynamic]Terrain_Structure_Instance,
	unlocked_world_areas: [dynamic]u64,

	scratch: struct {
		all_entities: []Entity_Handle,
	}
}

INVENTORY_SLOT_COUNT :: 12
HOTBAR_SLOT_COUNT :: 6
HOTBAR_SLOT_START :: INVENTORY_SLOT_COUNT - HOTBAR_SLOT_COUNT
AUTO_PICKUP_RADIUS: f32 : 40
DROP_OUTSIDE_PICKUP_RADIUS: f32 : AUTO_PICKUP_RADIUS + 6
INTERACT_RANGE: f32 : 40
PLACE_PREVIEW_RANGE: f32 : INTERACT_RANGE * 2
ENTITY_GRID_SIZE: f32 : 32
HITBOX_CORNER_CUT: f32 : 9
TREE_WOOD_HIT_DROP_CHANCE: f32 : 0.15
DURABILITY_REGEN_DELAY_SEC: f64 : 0.5
DURABILITY_REGEN_PER_SEC: f32 : 2.0
SPROUT_GROWTH_BASE_SEC: f64 : 60.0
SPROUT_GROWTH_JITTER_SEC: f64 : 20.0
SAPLING_GROWTH_BASE_SEC: f64 : 120.0
SAPLING_GROWTH_JITTER_SEC: f64 : 40.0
GROWTH_RETRY_DELAY_SEC: f64 : 4.0
ITEM_DROP_BOUNCE_SPEED: f32 : 95
ITEM_DROP_BOUNCE_DRAG: f32 : 6.5
ITEM_DROP_PICKUP_DELAY_SEC: f64 : 0.25
HIT_FLASH_DURATION_SEC: f32 : 0.12
HIT_DROP_MAX_FROM_EDGE: f32 : 40
LOW_DURABILITY_FLASH_THRESHOLD :: 3
LOW_DURABILITY_FLASH_ALPHA_MULT: f32 : 2.0
LOW_DURABILITY_FLASH_DECAY_MULT: f32 : 0.45
PLAYER_MOVE_SPEED: f32 : 112.0
BIOME_CHUNK_SIZE_TILES :: 64
STRUCTURE_CHUNK_INNER_AREA_TILES :: 15
VEG_SPAWN_RADIUS_CHUNKS :: 2
GRASS_SPAWNS_PER_CHUNK :: 11
GRASS_SPAWN_TRIES_PER_CHUNK :: 28
TREE_SPAWNS_PER_CHUNK :: 3
TREE_SPAWN_TRIES_PER_CHUNK :: 16
VEG_MIN_DIST_GRASS: f32 : 12
VEG_MIN_DIST_TREE: f32 : 22

UI_OVERLAY_INVENTORY : u32 : 1 << 0
UI_OVERLAY_PAUSE : u32 : 1 << 1

Item_Kind :: enum u8 {
	nil,
	wood,
	stone,
	fiber,
	stick,
	rope,
	sapling,
	stone_blade,
	stone_multitool,
	oblisk_fragment,
	oblisk_core,
	dagger_item,
}

Inventory_Slot :: struct {
	item: Item_Kind,
	count: int,
}

Inventory_State :: struct {
	open: bool,
	equipped_slot: int, // index into slots
	slots: [INVENTORY_SLOT_COUNT]Inventory_Slot,
	dragging: bool,
	drag_from_slot: int, // index in inventory/crafting arrays
	drag_from_kind: Drag_From_Kind,
	drag_slot: Inventory_Slot,
	crafting_slots: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot,
	crafting_output: Inventory_Slot,
	crafting_recipe_index: int,
	right_drag_last_slot: int,
	right_drag_last_kind: Drag_From_Kind,
}

CRAFT_INPUT_COLS :: 2
CRAFT_INPUT_ROWS :: 3
CRAFT_INPUT_SLOT_COUNT :: CRAFT_INPUT_COLS * CRAFT_INPUT_ROWS
MAX_TERRAIN_STRUCTURES :: 64
MAX_TERRAIN_STRUCTURE_ROWS :: 64
MAX_TERRAIN_STRUCTURE_COLS :: 64
WORLD_UNLOCK_AREA_SIZE_TILES :: 16
WORLD_UNLOCK_CAMERA_EDGE_MARGIN_TILES: f32 : 1.5

Drag_From_Kind :: enum u8 {
	none,
	inventory,
	craft_input,
	craft_output,
}

Crafting_Ingredient :: struct {
	item: Item_Kind,
	count: int,
}

Crafting_Recipe :: struct {
	pattern: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot,
	output: Crafting_Ingredient,
}

crafting_recipes: [dynamic]Crafting_Recipe

Terrain_Tile_Kind :: enum u8 {
	empty,
	block,
	water,
}

Terrain_Tile :: struct {
	kind: Terrain_Tile_Kind,
	block_index: int,
	water_variant: int,
	water_flip_x: bool,
}

Terrain_Structure :: struct {
	name: string,
	rows: int,
	cols: int,
	tiles: [MAX_TERRAIN_STRUCTURE_ROWS][MAX_TERRAIN_STRUCTURE_COLS]Terrain_Tile,
}

Terrain_Structure_Instance :: struct {
	structure_index: int,
	origin_tile_x: int,
	origin_tile_y: int,
}

terrain_structures: [dynamic]Terrain_Structure

Water_Collision_Mask :: struct {
	width: int,
	height: int,
	alpha: [dynamic]u8,
}
MAX_WATER_VARIANTS :: 4
water_collision_masks: [MAX_WATER_VARIANTS+1]Water_Collision_Mask

Terrain_Block_Hitbox :: struct {
	offset: Vec2,
	size: Vec2,
}

Terrain_Block_Hitbox_Set :: struct {
	count: int,
	boxes: [8]Terrain_Block_Hitbox,
}
terrain_block_hitboxes: [TERRAIN_MAX_BLOCK_INDEX+1]Terrain_Block_Hitbox_Set

//
// action -> key mapping

action_map: map[Input_Action]Key_Code = {
	.left = .A,
	.right = .D,
	.up = .W,
	.down = .S,
	.click = .LEFT_MOUSE,
	.use = .RIGHT_MOUSE,
	.interact = .E,
}

Input_Action :: enum u8 {
	left,
	right,
	up,
	down,
	click,
	use,
	interact,
}

//
// entity system

MAX_BREAK_DROPS :: 4
Break_Drop :: struct {
	item: Item_Kind,
	count: int,
}

Entity :: struct {
	handle: Entity_Handle,
	kind: Entity_Kind,

	// todo, move this into static entity data
	update_proc: proc(^Entity),
	draw_proc: proc(Entity),

	// big sloppy entity state dump.
	// add whatever you need in here.
	pos: Vec2,
	last_known_x_dir: f32,
	flip_x: bool,
	draw_offset: Vec2,
	draw_pivot: utils.Pivot,
	rotation: f32,
	hit_flash: Vec4,
	sprite: Sprite_Name,
	anim_index: int,
  next_frame_end_time: f64,
  loop: bool,
	frame_duration: f32,
	is_active: bool,
	durability: int,
	durability_max: int,
	durability_regen_accum: f32,
	last_hit_time: f64,
	break_drops: [MAX_BREAK_DROPS]Break_Drop,
	break_drop_len: int,
	blocks_player: bool,
	on_hit_proc: proc(^Entity, ^Entity),
	pickup_item: Item_Kind,
	pickup_count: int,
	pickup_ready_time: f64,
	vel: Vec2,
	max_distance: f32,
	distance_travelled: f32,
	move_target: Vec2,
	has_move_target: bool,
	queued_move_target: Vec2,
	has_queued_move_target: bool,
	pending_interact: Entity_Handle,
	has_pending_interact: bool,
	pending_place_item: Item_Kind,
	pending_place_pos: Vec2,
	has_pending_place: bool,
	growth_ready_time: f64,
	
	// this gets zeroed every frame. Useful for passing data to other systems.
	scratch: struct {
		col_override: Vec4,
	}
}

Entity_Kind :: enum {
	nil,
	player,
	oblisk_ent,
	tree_ent,
	sapling_ent,
	sprout_ent,
	grass_ent,
	item_pickup,
	dagger_projectile,
	movement_indicator_fx,
}

entity_setup :: proc(e: ^Entity, kind: Entity_Kind) {
	// entity defaults
	e.draw_proc = draw_entity_default
	e.draw_pivot = .bottom_center

	switch kind {
		case .nil:
		case .player: setup_player(e)
		case .oblisk_ent: setup_oblisk_ent(e)
		case .tree_ent: setup_tree_ent(e)
		case .sapling_ent: setup_sapling_ent(e)
		case .sprout_ent: setup_sprout_ent(e)
		case .grass_ent: setup_grass_ent(e)
		case .item_pickup: setup_item_pickup(e)
		case .dagger_projectile: setup_dagger_projectile(e)
		case .movement_indicator_fx: setup_movement_indicator_fx(e)
	}
}

//
// game :draw related things

Quad_Flags :: enum u8 {
	// #shared with the shader.glsl definition
	background_pixels = (1<<0),
	flag2 = (1<<1),
	flag3 = (1<<2),
}

ZLayer :: enum u8 {
	// Can add as many layers as you want in here.
	// Quads get sorted and drawn lowest to highest.
	// When things are on the same layer, they follow normal call order.
	nil,
	background,
	shadow,
	playspace,
	vfx,
	ui,
	tooltip,
	pause_menu,
	top,
}

Sprite_Name :: enum {
	nil,
	player_still,
	shadow_medium,
	bg_repeat_tex0,
	forest_grass_texture,
	desert_bg_tile,
	plains_bg_tile,
	plains_0,
	plains_1,
	plains_2,
	plains_3,
	plains_4,
	tilemap_color1,
	forest_bg_tile,
	ruins_bg_tile,
	grass,
	water,
	water_1,
	water_2,
	water_3,
	water_4,
	dagger_item,
	dagger_item_flying,
	movement_indicator,
	player_death,
	player_run,
	player_idle,
	wood,
	stone,
	sticks,
	fibre,
	rope,
	stone_blade,
	stone_multitool,
	stone_multitool_swing,
	sapling,
	sprout,
	tree,
	oblisk,
	oblisk_rest,
	oblisk_broken,

	// to add new sprites, just put the .png in the res/images folder
	// and add the name to the enum here
	//
	// we could auto-gen this based on all the .png's in the images folder
	// but I don't really see the point right now. It's not hard to type lol.
}

sprite_data: [Sprite_Name]Sprite_Data = #partial {
	.player_still = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
	.player_idle = {frame_count=2, overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
	.player_run = {frame_count=3, overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
	.player_death = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
	.dagger_item = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.dagger_item_flying = {frame_count=7},
	.wood = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.stone = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.sticks = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.fibre = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.rope = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.stone_blade = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.stone_multitool = {overlap_box_size=Vec2{8, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.center_center},
	.stone_multitool_swing = {frame_count=4},
	.movement_indicator = {frame_count=6},
	.grass = {frame_count=6},
	.sprout = {overlap_box_size=Vec2{10, 8}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
	.sapling = {overlap_box_size=Vec2{16, 14}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
	.tree = {overlap_box_size=Vec2{48, 103}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},

	.oblisk = {overlap_box_size=Vec2{40, 60}, overlap_box_offset=Vec2{0, 10}, overlap_box_pivot=.bottom_center},
	.oblisk_rest = {overlap_box_size=Vec2{40, 60}, overlap_box_offset=Vec2{0, 10}, overlap_box_pivot=.bottom_center},
	.oblisk_broken = {overlap_box_size=Vec2{12, 12}, overlap_box_offset=Vec2{0, 0}, overlap_box_pivot=.bottom_center},
}

Sprite_Data :: struct {
	frame_count: int,
	offset: Vec2,
	pivot: utils.Pivot,
	overlap_box_size: Vec2,
	overlap_box_offset: Vec2,
	overlap_box_pivot: utils.Pivot,
}

Frame_Anim_Meta :: struct {
	frame_widths: [dynamic]f32,
	frame_center_offsets: [dynamic]Vec2,
}
frame_anim_meta: [Sprite_Name]Frame_Anim_Meta

get_sprite_offset :: proc(img: Sprite_Name) -> (offset: Vec2, pivot: utils.Pivot) {
	data := sprite_data[img]
	offset = data.offset
	pivot = data.pivot
	return
}

// #cleanup todo, this is kinda yuckie living in the bald-user
get_frame_count :: proc(sprite: Sprite_Name) -> int {
	if len(frame_anim_meta[sprite].frame_widths) > 0 {
		return len(frame_anim_meta[sprite].frame_widths)
	}

	frame_count := sprite_data[sprite].frame_count
	if frame_count == 0 {
		frame_count = 1
	}
	return frame_count
}

get_frame_width_px_for_sprite :: proc(sprite: Sprite_Name, anim_index: int, total_width: f32) -> f32 {
	meta := frame_anim_meta[sprite]
	if len(meta.frame_widths) > 0 {
		total_meta_width: f32
		for w in meta.frame_widths {
			total_meta_width += w
		}
		if total_meta_width > 0 {
			idx := clamp(anim_index, 0, len(meta.frame_widths)-1)
			return total_width * (meta.frame_widths[idx] / total_meta_width)
		}
	}

	return total_width / f32(get_frame_count(sprite))
}

get_anim_frame_uv :: proc(sprite: Sprite_Name, base_uv: Vec4, anim_index: int) -> Vec4 {
	meta := frame_anim_meta[sprite]
	if len(meta.frame_widths) > 0 {
		total_meta_width: f32
		for w in meta.frame_widths {
			total_meta_width += w
		}
		if total_meta_width <= 0 {
			return base_uv
		}

		idx := clamp(anim_index, 0, len(meta.frame_widths)-1)
		offset_px: f32
		for i in 0..<idx {
			offset_px += meta.frame_widths[i]
		}
		frame_px := meta.frame_widths[idx]

		uv_width := base_uv.z - base_uv.x
		u0 := base_uv.x + (offset_px / total_meta_width) * uv_width
		u1 := u0 + (frame_px / total_meta_width) * uv_width
		return Vec4{u0, base_uv.y, u1, base_uv.w}
	}

	frame_count := get_frame_count(sprite)
	if frame_count <= 1 {
		return base_uv
	}

	uv_size := shape.rect_size(base_uv)
	uv_frame_size := uv_size * Vec2{1.0/f32(frame_count), 1.0}
	idx := clamp(anim_index, 0, frame_count-1)
	uv := base_uv
	uv.zw = uv.xy + uv_frame_size
	uv = shape.rect_shift(uv, Vec2{f32(idx)*uv_frame_size.x, 0})
	return uv
}

parse_positive_ints :: proc(s: string) -> [dynamic]f32 {
	out := make([dynamic]f32, 0, 8, allocator=context.allocator)
	value := 0
	in_num := false
	for c in s {
		if c >= '0' && c <= '9' {
			value = value*10 + int(c-'0')
			in_num = true
		} else if in_num {
			append(&out, f32(value))
			value = 0
			in_num = false
		}
	}
	if in_num {
		append(&out, f32(value))
	}
	return out
}

parse_vec2_pairs :: proc(s: string) -> [dynamic]Vec2 {
	out := make([dynamic]Vec2, 0, 8, allocator=context.allocator)
	for pair in strings.split(s, ",") {
		if len(pair) == 0 do continue
		xy := strings.split(pair, ":")
		if len(xy) < 2 do continue

		x, x_ok := parse_simple_f32(xy[0])
		y, y_ok := parse_simple_f32(xy[1])
		if x_ok && y_ok {
			append(&out, Vec2{x, y})
		}
	}
	return out
}

parse_simple_f32 :: proc(s: string) -> (v: f32, ok: bool) #optional_ok {
	if len(s) == 0 {
		return 0, false
	}

	i := 0
	sign: f32 = 1
	if s[i] == '-' {
		sign = -1
		i += 1
	} else if s[i] == '+' {
		i += 1
	}

	int_part: f32
	has_digit := false
	for i < len(s) {
		c := s[i]
		if c < '0' || c > '9' {
			break
		}
		has_digit = true
		int_part = int_part*10 + f32(c-'0')
		i += 1
	}

	frac_part: f32
	frac_scale: f32 = 1
	if i < len(s) && s[i] == '.' {
		i += 1
		for i < len(s) {
			c := s[i]
			if c < '0' || c > '9' {
				break
			}
			has_digit = true
			frac_part = frac_part*10 + f32(c-'0')
			frac_scale *= 10
			i += 1
		}
	}

	if !has_digit {
		return 0, false
	}

	// ignore trailing whitespace/newline chars
	for i < len(s) {
		c := s[i]
		if c != ' ' && c != '\t' && c != '\r' && c != '\n' {
			return 0, false
		}
		i += 1
	}

	return sign * (int_part + frac_part/frac_scale), true
}

trim_ascii_ws :: proc(s: string) -> string {
	start := 0
	for start < len(s) {
		c := s[start]
		if c != ' ' && c != '\t' && c != '\r' && c != '\n' {
			break
		}
		start += 1
	}

	stop := len(s)
	for stop > start {
		c := s[stop-1]
		if c != ' ' && c != '\t' && c != '\r' && c != '\n' {
			break
		}
		stop -= 1
	}

	return s[start:stop]
}

parse_positive_int_str :: proc(s: string) -> (v: int, ok: bool) #optional_ok {
	ss := trim_ascii_ws(s)
	if len(ss) == 0 {
		return 0, false
	}

	value := 0
	for c in ss {
		if c < '0' || c > '9' {
			return 0, false
		}
		value = value*10 + int(c-'0')
	}
	return value, true
}

parse_signed_int_str :: proc(s: string) -> (v: int, ok: bool) #optional_ok {
	ss := trim_ascii_ws(s)
	if len(ss) == 0 {
		return 0, false
	}

	sign := 1
	start := 0
	if ss[0] == '-' {
		sign = -1
		start = 1
	}
	if start >= len(ss) {
		return 0, false
	}

	value := 0
	for i := start; i < len(ss); i += 1 {
		c := ss[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		value = value*10 + int(c-'0')
	}
	return value * sign, true
}

item_kind_from_token :: proc(tok: string) -> (item: Item_Kind, ok: bool) #optional_ok {
	t := trim_ascii_ws(tok)
	switch t {
	case "wood": return .wood, true
	case "stone": return .stone, true
	case "fiber": return .fiber, true
	case "stick": return .stick, true
	case "rope": return .rope, true
	case "sapling": return .sapling, true
	case "stone_blade": return .stone_blade, true
	case "stone_multitool": return .stone_multitool, true
	case "oblisk_fragment": return .oblisk_fragment, true
	case "oblisk_core": return .oblisk_core, true
	case "dagger_item": return .dagger_item, true
	case:
		return .nil, false
	}
}

parse_ingredient_token :: proc(tok: string) -> (Crafting_Ingredient, bool) {
	t := trim_ascii_ws(tok)
	if len(t) == 0 {
		return {}, false
	}

	sep := strings.index(t, ":")
	item_tok := t
	count_tok := "1"
	if sep >= 0 {
		item_tok = trim_ascii_ws(t[:sep])
		count_tok = trim_ascii_ws(t[sep+1:])
	}

	item, item_ok := item_kind_from_token(item_tok)
	if !item_ok {
		return {}, false
	}
	count, count_ok := parse_positive_int_str(count_tok)
	if !count_ok || count <= 0 {
		return {}, false
	}

	return Crafting_Ingredient{item=item, count=count}, true
}

parse_recipe_pattern :: proc(side: string) -> (pattern: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot, ok: bool) {
	rows := strings.split(side, "|")
	if len(rows) != CRAFT_INPUT_ROWS {
		return pattern, false
	}

	idx := 0
	for r in 0..<CRAFT_INPUT_ROWS {
		cells := strings.split(rows[r], ",")
		if len(cells) != CRAFT_INPUT_COLS {
			return pattern, false
		}

		for c in 0..<CRAFT_INPUT_COLS {
			cell := trim_ascii_ws(cells[c])
			if len(cell) == 0 || cell == "_" || cell == "." || cell == "empty" {
				pattern[idx] = {}
			} else {
				ing, ing_ok := parse_ingredient_token(cell)
				if !ing_ok {
					return pattern, false
				}
				pattern[idx] = {item=ing.item, count=ing.count}
			}
			idx += 1
		}
	}

	for slot in pattern {
		if slot.item != .nil && slot.count > 0 {
			return pattern, true
		}
	}

	return pattern, false
}

push_recipe :: proc(pattern: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot, output: Crafting_Ingredient) {
	append(&crafting_recipes, Crafting_Recipe{pattern=pattern, output=output})
}

load_default_crafting_recipes :: proc() {
	crafting_recipes = make([dynamic]Crafting_Recipe, 0, 8, allocator=context.allocator)

	p0: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot
	p0[0] = {item=.wood, count=1}
	p0[2] = {item=.wood, count=1}
	push_recipe(p0, {item=.stick, count=2})

	p1: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot
	p1[0] = {item=.fiber, count=1}
	p1[2] = {item=.fiber, count=1}
	push_recipe(p1, {item=.rope, count=1})

	p2: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot
	p2[0] = {item=.stone, count=1}
	p2[2] = {item=.stick, count=1}
	push_recipe(p2, {item=.stone_blade, count=1})

	p3: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot
	p3[0] = {item=.stone_blade, count=1}
	p3[2] = {item=.stick, count=1}
	p3[4] = {item=.rope, count=1}
	push_recipe(p3, {item=.dagger_item, count=1})
}

load_crafting_recipes :: proc() {
	crafting_recipes = make([dynamic]Crafting_Recipe, 0, 8, allocator=context.allocator)

	path := "res/data/crafting_recipes.txt"
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		load_default_crafting_recipes()
		return
	}

	text := string(data)
	line_no := 0
	for raw_line in strings.split(text, "\n") {
		line_no += 1
		line := trim_ascii_ws(raw_line)
		if len(line) == 0 do continue
		if strings.has_prefix(line, "#") do continue

		arrow := strings.index(line, "->")
		if arrow < 0 {
			log.warnf("crafting_recipes line %v invalid (missing ->): %q", line_no, line)
			continue
		}

		left := trim_ascii_ws(line[:arrow])
		right := trim_ascii_ws(line[arrow+2:])
		pattern, in_ok := parse_recipe_pattern(left)
		if !in_ok {
			log.warnf("crafting_recipes line %v invalid pattern: %q", line_no, left)
			continue
		}
		output, out_ok := parse_ingredient_token(right)
		if !out_ok {
			log.warnf("crafting_recipes line %v invalid output: %q", line_no, right)
			continue
		}

		push_recipe(pattern, output)
	}

	if len(crafting_recipes) == 0 {
		log.warn("no valid crafting recipes loaded; using defaults")
		load_default_crafting_recipes()
	}
}

compact_no_ws :: proc(s: string) -> string {
	out := make([dynamic]u8, 0, len(s), allocator=context.temp_allocator)
	for i in 0..<len(s) {
		c := s[i]
		if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
			continue
		}
		append(&out, c)
	}
	return string(out[:])
}

parse_terrain_tile_token :: proc(tok: string) -> (Terrain_Tile, bool) {
	t := trim_ascii_ws(tok)
	if len(t) == 0 {
		return {}, false
	}
	if len(t) >= 2 {
		if (t[0] == '"' && t[len(t)-1] == '"') || (t[0] == '\'' && t[len(t)-1] == '\'') {
			t = t[1:len(t)-1]
		}
	}

	flip_x := false
	if len(t) >= 2 && strings.has_suffix(t, "a") {
		flip_x = true
		t = t[:len(t)-1]
	}

	if t == "water" || t == "water_1" || t == "0" {
		return Terrain_Tile{kind=.water, water_variant=1, water_flip_x=flip_x}, true
	}
	if t == "water_2" || t == "-1" {
		return Terrain_Tile{kind=.water, water_variant=2, water_flip_x=flip_x}, true
	}
	if t == "water_3" || t == "-2" {
		return Terrain_Tile{kind=.water, water_variant=3, water_flip_x=flip_x}, true
	}
	if t == "water_4" || t == "-3" {
		return Terrain_Tile{kind=.water, water_variant=4, water_flip_x=flip_x}, true
	}
	if t == "_" || t == "." || t == "empty" {
		return Terrain_Tile{kind=.empty}, true
	}

	signed, signed_ok := parse_signed_int_str(t)
	if signed_ok && signed <= 0 && signed >= -3 {
		return Terrain_Tile{kind=.water, water_variant=1-signed, water_flip_x=flip_x}, true
	}

	block_index, ok := parse_positive_int_str(t)
	if !ok {
		return {}, false
	}
	if block_index < 1 || block_index > TERRAIN_MAX_BLOCK_INDEX {
		return {}, false
	}
	return Terrain_Tile{kind=.block, block_index=block_index}, true
}

parse_terrain_structure_expr :: proc(name: string, expr_raw: string) -> bool {
	expr := compact_no_ws(expr_raw)
	if len(expr) < 4 || !strings.has_prefix(expr, "[[") || !strings.has_suffix(expr, "]]") {
		log.warnf("terrain structure %q invalid format", name)
		return false
	}

	if len(terrain_structures) >= MAX_TERRAIN_STRUCTURES {
		log.warnf("too many terrain structures, max=%v", MAX_TERRAIN_STRUCTURES)
		return false
	}

	body := expr[2:len(expr)-2]
	row_strs := strings.split(body, "],[")
	if len(row_strs) == 0 || len(row_strs) > MAX_TERRAIN_STRUCTURE_ROWS {
		log.warnf("terrain structure %q invalid row count=%v", name, len(row_strs))
		return false
	}

	st := Terrain_Structure{name=name}
	st.rows = len(row_strs)

	for r in 0..<len(row_strs) {
		cells := strings.split(row_strs[r], ",")
		if len(cells) == 0 || len(cells) > MAX_TERRAIN_STRUCTURE_COLS {
			log.warnf("terrain structure %q row %v invalid col count=%v", name, r, len(cells))
			return false
		}
		if r == 0 {
			st.cols = len(cells)
		} else if len(cells) != st.cols {
			log.warnf("terrain structure %q rows have mismatched col counts", name)
			return false
		}

		for c in 0..<len(cells) {
			tile, ok := parse_terrain_tile_token(cells[c])
			if !ok {
				log.warnf("terrain structure %q has invalid token %q at [%v,%v]", name, cells[c], r, c)
				return false
			}
			st.tiles[r][c] = tile
		}
	}

	append(&terrain_structures, st)
	return true
}

load_default_terrain_structures :: proc() {
	terrain_structures = make([dynamic]Terrain_Structure, 0, 4, allocator=context.allocator)
	_ = parse_terrain_structure_expr("default_flat", "[[11]]")
}

load_terrain_structures :: proc() {
	terrain_structures = make([dynamic]Terrain_Structure, 0, 16, allocator=context.allocator)

	path := "res/data/terrain_structures.txt"
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		log.warnf("terrain_structures not found at %q, using defaults", path)
		load_default_terrain_structures()
		return
	}

	text := string(data)
	lines := strings.split(text, "\n")
	i := 0
	for i < len(lines) {
		line := trim_ascii_ws(lines[i])
		i += 1

		if len(line) == 0 || strings.has_prefix(line, "#") {
			continue
		}

		eq := strings.index(line, "=")
		if eq < 0 {
			log.warnf("terrain_structures invalid line (missing '='): %q", line)
			continue
		}

		name := trim_ascii_ws(line[:eq])
		expr := trim_ascii_ws(line[eq+1:])
		expr_buf := make([dynamic]u8, 0, len(expr)+64, allocator=context.temp_allocator)
		append(&expr_buf, expr)
		bracket_balance := strings.count(expr, "[") - strings.count(expr, "]")

		for bracket_balance > 0 && i < len(lines) {
			next_line := trim_ascii_ws(lines[i])
			i += 1
			if len(next_line) == 0 || strings.has_prefix(next_line, "#") {
				continue
			}
			append(&expr_buf, next_line)
			bracket_balance += strings.count(next_line, "[") - strings.count(next_line, "]")
		}

		if len(name) == 0 {
			log.warnf("terrain_structures has unnamed entry: %q", line)
			continue
		}

		_ = parse_terrain_structure_expr(name, string(expr_buf[:]))
	}

	if len(terrain_structures) == 0 {
		log.warn("no valid terrain structures loaded; using defaults")
		load_default_terrain_structures()
	}
}

water_sprite_for_variant :: proc(variant: int) -> Sprite_Name {
	switch variant {
	case 2: return .water_2
	case 3: return .water_3
	case 4: return .water_4
	case:
		// Prefer explicit water_1 if present, otherwise legacy water.png.
		return .water_1 if sprite_is_loaded(.water_1) else .water
	}
}

water_mask_for_variant :: proc(variant: int) -> ^Water_Collision_Mask {
	v := clamp(variant, 1, MAX_WATER_VARIANTS)
	mask := &water_collision_masks[v]
	if mask.width > 0 && mask.height > 0 && len(mask.alpha) > 0 {
		return mask
	}
	fallback := &water_collision_masks[1]
	if fallback.width > 0 && fallback.height > 0 && len(fallback.alpha) > 0 {
		return fallback
	}
	return mask
}

load_one_water_collision_mask :: proc(variant: int, path: string) -> bool {
	if variant < 1 || variant > MAX_WATER_VARIANTS {
		return false
	}

	water_collision_masks[variant] = {}
	png_data, png_err := os.read_entire_file_from_path(path, context.temp_allocator)
	if png_err != nil || len(png_data) == 0 {
		return false
	}

	stbi.set_flip_vertically_on_load(1)
	width, height, channels: i32
	img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)
	if img_data == nil || width <= 0 || height <= 0 {
		return false
	}
	defer stbi.image_free(img_data)

	alpha := make([dynamic]u8, 0, int(width)*int(height), allocator=context.allocator)
	for i in 0..<int(width)*int(height) {
		append(&alpha, img_data[i*4 + 3])
	}

	water_collision_masks[variant].width = int(width)
	water_collision_masks[variant].height = int(height)
	water_collision_masks[variant].alpha = alpha
	return true
}

load_water_collision_masks :: proc() {
	for i in 0..=MAX_WATER_VARIANTS {
		water_collision_masks[i] = {}
	}

	if !load_one_water_collision_mask(1, "res/images/water_1.png") {
		if !load_one_water_collision_mask(1, "res/images/water.png") {
			log.warn("water collision mask missing water_1.png/water.png; using full-tile water collision fallback")
		}
	}
	for variant in 2..=MAX_WATER_VARIANTS {
		path := fmt.tprintf("res/images/water_%v.png", variant)
		_ = load_one_water_collision_mask(variant, path)
	}
}

load_sprite_frame_meta :: proc() {
	for sprite in Sprite_Name {
		if sprite == .nil do continue

		path := fmt.tprintf("res/images/%v.meta", sprite)
		data, err := os.read_entire_file_from_path(path, context.temp_allocator)
		if err != nil || len(data) == 0 {
			continue
		}

		text := string(data)
		start := strings.index(text, "frame_widths=")
		if start < 0 {
			continue
		}
		rest := text[start+len("frame_widths="):]
		end := strings.index(rest, "\n")
		if end >= 0 {
			rest = rest[:end]
		}

		widths := parse_positive_ints(rest)
		if len(widths) > 0 {
			frame_anim_meta[sprite].frame_widths = widths
		}

		offset_start := strings.index(text, "frame_center_offsets=")
		if offset_start >= 0 {
			offset_rest := text[offset_start+len("frame_center_offsets="):]
			offset_end := strings.index(offset_rest, "\n")
			if offset_end >= 0 {
				offset_rest = offset_rest[:offset_end]
			}

			offsets := parse_vec2_pairs(offset_rest)
			if len(offsets) > 0 {
				frame_anim_meta[sprite].frame_center_offsets = offsets
			}
		}
	}
}

get_anim_frame_center_offset :: proc(sprite: Sprite_Name, anim_index: int) -> Vec2 {
	offsets := frame_anim_meta[sprite].frame_center_offsets
	if len(offsets) == 0 {
		return {}
	}

	idx := clamp(anim_index, 0, len(offsets)-1)
	return offsets[idx]
}

get_sprite_center_mass :: proc(img: Sprite_Name) -> Vec2 {
	size := get_sprite_size(img)
	
	offset, pivot := get_sprite_offset(img)
	
	center := size * utils.scale_from_pivot(pivot)
	center -= offset
	
	return center
}

//
// main game procs

app_init :: proc() {
	load_sprite_frame_meta()
	load_crafting_recipes()
	load_terrain_structures()
	load_water_collision_masks()
	setup_terrain_block_hitboxes()
}

app_frame :: proc() {

	// right now we are just calling the game update, but in future this is where you'd do a big
	// "UX" switch for startup splash, main menu, settings, in-game, etc

	{
		// ui space example
		push_coord_space(get_screen_space())

		draw_inventory_ui()
		draw_pause_menu_ui()
	}

	sound_play_continuously("event:/ambiance", "")

	game_update()
	game_draw()

	volume :f32= 0.75
	sound_update(get_player().pos, volume)
}

draw_pause_menu_ui :: proc() {
	if !is_ui_overlay_open(UI_OVERLAY_PAUSE) {
		return
	}

	sx, sy := screen_pivot(.center_center)
	screen_rect := shape.rect_make(Vec2{sx, sy}, Vec2{f32(GAME_RES_WIDTH), f32(GAME_RES_HEIGHT)}, pivot=.center_center)
	draw_rect(screen_rect, col=Vec4{0.5, 0.5, 0.5, 0.35}, z_layer=.pause_menu)

	cx, cy := screen_pivot(.center_center)
	panel_size := Vec2{190, 236}
	panel := shape.rect_make(Vec2{cx, cy}, panel_size, pivot=.center_center)
	draw_rect(panel, col=Vec4{0.02, 0.02, 0.02, 0.92}, outline_col=Vec4{1, 1, 1, 0.3}, z_layer=.pause_menu)
	draw_text(Vec2{cx, cy + 76}, "Paused", pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.95}, drop_shadow_col=Vec4{})

	button_size := Vec2{78, 18}
	resume_rect := shape.rect_make(Vec2{cx, cy + 48}, button_size, pivot=.center_center)
	resume_hover, resume_pressed := raw_button(resume_rect)
	resume_col := Vec4{0.1, 0.1, 0.1, 0.9}
	if resume_hover {
		resume_col = Vec4{0.16, 0.16, 0.16, 0.95}
	}
	draw_rect(resume_rect, col=resume_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	resume_center := (resume_rect.xy + resume_rect.zw) * 0.5
	draw_text(resume_center, "Resume", pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.95}, drop_shadow_col=Vec4{}, scale=0.5)
	if resume_pressed {
		close_all_ui_overlays()
	}

	debug_button_size := Vec2{124, 16}
	debug_start := Vec2{cx, cy + 22}

	hitboxes_rect := shape.rect_make(debug_start, debug_button_size, pivot=.center_center)
	hitboxes_hover, hitboxes_pressed := raw_button(hitboxes_rect)
	if hitboxes_pressed {
		ctx.gs.debug_show_hitboxes = !ctx.gs.debug_show_hitboxes
	}
	hitboxes_col := Vec4{0.05, 0.05, 0.05, 0.78}
	if hitboxes_hover {
		hitboxes_col = Vec4{0.2, 0.2, 0.2, 0.85}
	}
	draw_rect(hitboxes_rect, col=hitboxes_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	hitboxes_label := ctx.gs.debug_show_hitboxes ? "Hitboxes: ON" : "Hitboxes: OFF"
	hitboxes_center := (hitboxes_rect.xy + hitboxes_rect.zw) * 0.5
	draw_text(hitboxes_center, hitboxes_label, pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)

	overlap_rect := shape.rect_make(debug_start + Vec2{0, -18}, debug_button_size, pivot=.center_center)
	overlap_hover, overlap_pressed := raw_button(overlap_rect)
	if overlap_pressed {
		ctx.gs.debug_show_overlap_boxes = !ctx.gs.debug_show_overlap_boxes
	}
	overlap_col := Vec4{0.05, 0.05, 0.05, 0.78}
	if overlap_hover {
		overlap_col = Vec4{0.2, 0.2, 0.2, 0.85}
	}
	draw_rect(overlap_rect, col=overlap_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	overlap_label := ctx.gs.debug_show_overlap_boxes ? "Overlap: ON" : "Overlap: OFF"
	overlap_center := (overlap_rect.xy + overlap_rect.zw) * 0.5
	draw_text(overlap_center, overlap_label, pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)

	dura_rect := shape.rect_make(debug_start + Vec2{0, -36}, debug_button_size, pivot=.center_center)
	dura_hover, dura_pressed := raw_button(dura_rect)
	if dura_pressed {
		ctx.gs.debug_show_durability = !ctx.gs.debug_show_durability
	}
	dura_col := Vec4{0.05, 0.05, 0.05, 0.78}
	if dura_hover {
		dura_col = Vec4{0.2, 0.2, 0.2, 0.85}
	}
	draw_rect(dura_rect, col=dura_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	dura_label := ctx.gs.debug_show_durability ? "Durability: ON" : "Durability: OFF"
	dura_center := (dura_rect.xy + dura_rect.zw) * 0.5
	draw_text(dura_center, dura_label, pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)

	grid_rect := shape.rect_make(debug_start + Vec2{0, -54}, debug_button_size, pivot=.center_center)
	grid_hover, grid_pressed := raw_button(grid_rect)
	if grid_pressed {
		ctx.gs.debug_show_grid = !ctx.gs.debug_show_grid
	}
	grid_col := Vec4{0.05, 0.05, 0.05, 0.78}
	if grid_hover {
		grid_col = Vec4{0.2, 0.2, 0.2, 0.85}
	}
	draw_rect(grid_rect, col=grid_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	grid_label := ctx.gs.debug_show_grid ? "Grid: ON" : "Grid: OFF"
	grid_center := (grid_rect.xy + grid_rect.zw) * 0.5
	draw_text(grid_center, grid_label, pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)

	growth_rect := shape.rect_make(debug_start + Vec2{0, -72}, debug_button_size, pivot=.center_center)
	growth_hover, growth_pressed := raw_button(growth_rect)
	if growth_pressed {
		ctx.gs.debug_show_growth = !ctx.gs.debug_show_growth
	}
	growth_col := Vec4{0.05, 0.05, 0.05, 0.78}
	if growth_hover {
		growth_col = Vec4{0.2, 0.2, 0.2, 0.85}
	}
	draw_rect(growth_rect, col=growth_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	growth_label := ctx.gs.debug_show_growth ? "Growth: ON" : "Growth: OFF"
	growth_center := (growth_rect.xy + growth_rect.zw) * 0.5
	draw_text(growth_center, growth_label, pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)

	player := get_player()
	area_label := "Area: n/a"
	player_area_x, player_area_y := 0, 0
	player_valid := is_valid(player^)
	if player_valid {
		player_area_x, player_area_y = world_area_for_world_pos(player.pos)
		area_label = fmt.tprintf("Area: %v,%v", player_area_x, player_area_y)
	}
	draw_text(Vec2{cx, cy - 74}, area_label, pivot=.center_center, z_layer=.pause_menu, col=Vec4{0.9, 0.95, 1.0, 0.9}, drop_shadow_col=Vec4{}, scale=0.45)

	unlock_here_rect := shape.rect_make(Vec2{cx, cy - 90}, Vec2{124, 16}, pivot=.center_center)
	unlock_here_hover, unlock_here_pressed := raw_button(unlock_here_rect)
	unlock_here_col := Vec4{0.05, 0.08, 0.05, 0.78}
	if unlock_here_hover {
		unlock_here_col = Vec4{0.16, 0.22, 0.16, 0.86}
	}
	draw_rect(unlock_here_rect, col=unlock_here_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	draw_text((unlock_here_rect.xy+unlock_here_rect.zw)*0.5, "Unlock Here", pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)
	if unlock_here_pressed && player_valid {
		_ = unlock_world_area(player_area_x, player_area_y)
	}

	unlock_adj_rect := shape.rect_make(Vec2{cx, cy - 108}, Vec2{124, 16}, pivot=.center_center)
	unlock_adj_hover, unlock_adj_pressed := raw_button(unlock_adj_rect)
	unlock_adj_col := Vec4{0.05, 0.08, 0.05, 0.78}
	if unlock_adj_hover {
		unlock_adj_col = Vec4{0.16, 0.22, 0.16, 0.86}
	}
	draw_rect(unlock_adj_rect, col=unlock_adj_col, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.pause_menu)
	draw_text((unlock_adj_rect.xy+unlock_adj_rect.zw)*0.5, "Unlock Adjacent", pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{}, scale=0.5)
	if unlock_adj_pressed && player_valid {
		unlock_world_area_with_adjacent(player_area_x, player_area_y)
	}
}

app_shutdown :: proc() {
	// called on exit
}

game_update :: proc() {
	ctx.gs.scratch = {} // auto-zero scratch for each update
	defer {
		// update at the end
		ctx.gs.game_time_elapsed += f64(ctx.delta_t)
		ctx.gs.ticks += 1
	}

	// this'll be using the last frame's camera position, but it's fine for most things
	push_coord_space(get_world_space())

	if key_pressed(.ESC) {
		consume_key_pressed(.ESC)
		if is_any_ui_overlay_open() {
			close_all_ui_overlays()
		} else {
			set_ui_overlay_open(UI_OVERLAY_PAUSE, true)
		}
	}

	// setup world for first game tick
	if ctx.gs.ticks == 0 {
		player := entity_create(.player)
		ctx.gs.player_handle = player.handle
		ctx.gs.inventory.equipped_slot = HOTBAR_SLOT_START
		ctx.gs.debug_show_grid = false
		ctx.gs.terrain_structure_instances = make([dynamic]Terrain_Structure_Instance, 0, 32, allocator=context.allocator)
		ctx.gs.unlocked_world_areas = make([dynamic]u64, 0, 64, allocator=context.allocator)
		player.pos = manual_spawn_world_pos_for_hitbox(Vec2{0, 0}, Vec2{8, 8}, .bottom_center)
		_ = unlock_world_area_for_world_pos(player.pos)

		oblisk := entity_create(.oblisk_ent)
		oblisk.pos = manual_spawn_world_pos_for_hitbox(Vec2{64, 0}, Vec2{40, 40}, .bottom_center)
		tree := entity_create(.tree_ent)
		tree.pos = manual_spawn_world_pos_for_hitbox(Vec2{26, 0}, Vec2{50, 30}, .bottom_center)
		sapling := entity_create(.sapling_ent)
		sapling.pos = manual_spawn_world_pos_for_hitbox(Vec2{-40, 0}, Vec2{18, 13}, .bottom_center)
		sprout := entity_create(.sprout_ent)
		sprout.pos = manual_spawn_world_pos_for_hitbox(Vec2{-80, 0}, Vec2{15, 10}, .bottom_center)

		spawn_item_pickup(.wood, 4, manual_spawn_world_pos(Vec2{-68, 8}))
		spawn_item_pickup(.stone, 3, manual_spawn_world_pos(Vec2{-86, 8}))
		spawn_item_pickup(.fiber, 4, manual_spawn_world_pos(Vec2{-104, 8}))
		spawn_item_pickup(.stone_multitool, 1, manual_spawn_world_pos(Vec2{-55, 6}))
		
	}
	spawn_vegetation_near_player_chunks()

	if is_game_paused() {
		return
	}

	rebuild_scratch_helpers()
	
	// big :update time
	for handle in get_all_ents() {
		e := entity_from_handle(handle)

		update_entity_animation(e)

		if e.update_proc != nil {
			e.update_proc(e)
		}
		update_entity_durability_regen(e)
		update_entity_hit_flash(e)
	}
	update_player_swing_fx()

	apply_entity_grid_snap()

	resolve_player_vs_hitboxes()
	inventory_update()
	try_throw_equipped_dagger()

	if key_pressed(.RIGHT_MOUSE) && !is_any_ui_overlay_open() {
		consume_key_pressed(.RIGHT_MOUSE)

		player := get_player()
		if is_valid(player^) {
			target := mouse_pos_in_current_space()

			clicked_entity, clicked_entity_ok := find_entity_at_world_pos(target)
			if clicked_entity_ok {
				set_player_move_target_with_detour(player, clicked_entity.pos)
				player.pending_interact = clicked_entity.handle
				player.has_pending_interact = true
				player.has_pending_place = false
				player.pending_place_item = .nil
				spawn_movement_indicator(target)
			} else if !is_world_position_blocked_for_player(target) {
				set_player_move_target_with_detour(player, target)
				player.has_pending_interact = false
				player.pending_interact = {}
				player.has_pending_place = false
				player.pending_place_item = .nil
				spawn_movement_indicator(target)
			}
 		}
	}

	if key_pressed(.LEFT_MOUSE) && !is_any_ui_overlay_open() {
		pos := mouse_pos_in_current_space()
		begin_hold_hit_target_from_mouse(pos)

		if is_hit_cooldown_ready() {
			equipped_item, _ := get_equipped_item()
			began_place := try_begin_place_equipped_item(pos)
			if !began_place {
				did_hit, hit_handle := try_hit_entity_at_mouse(pos)
				if did_hit {
					ctx.gs.has_hold_hit_target = true
					ctx.gs.hold_hit_target = hit_handle
				} else {
					start_player_swing_fx()
				}
			} else {
				clear_hold_hit_target()
			}
			start_hit_cooldown_for_item(equipped_item)
			sound_play("event:/schloop", pos=pos)
		}

		consume_key_pressed(.LEFT_MOUSE)
	} else if key_pressed(.LEFT_MOUSE) && is_any_ui_overlay_open() {
		clear_hold_hit_target()
	}
	if key_released(.LEFT_MOUSE) {
		clear_hold_hit_target()
	}
	update_hold_hit_cycle()

	utils.animate_to_target_v2(&ctx.gs.cam_pos, get_follow_camera_target(get_player().pos), ctx.delta_t, rate=10)

	// ... add whatever other systems you need here to make epic game
}

rebuild_scratch_helpers :: proc() {
	// construct the list of all entities on the temp allocator
	// that way it's easier to loop over later on
	all_ents := make([dynamic]Entity_Handle, 0, len(ctx.gs.entities), allocator=context.temp_allocator)
	for &e in ctx.gs.entities {
		if !is_valid(e) do continue
		append(&all_ents, e.handle)
	}
	ctx.gs.scratch.all_entities = all_ents[:]
}

game_draw :: proc() {

	// this is so we can get the current pixel in the shader in world space (VERYYY useful)
	draw_frame.ndc_to_world_xform = get_world_space_camera() * linalg.inverse(get_world_space_proj())
	draw_frame.bg_repeat_tex0_atlas_uv = atlas_uv_from_sprite(.bg_repeat_tex0)

	// background thing
	{
		// identity matrices, so we're in clip space
		push_coord_space({proj=Matrix4(1), camera=Matrix4(1)})

		// draw rect that covers the whole screen
		draw_rect(shape.Rect{ -1, -1, 1, 1}, flags=.background_pixels) // we leave it in the hands of the shader
	}

	// world
	{
		push_coord_space(get_world_space())
		draw_world_terrain_tiles()
		if ctx.gs.debug_show_grid {
			draw_world_grid()
		}
		draw_placeable_range_circle()
		draw_placeable_preview()

		draw_order := make([dynamic]Entity_Handle, 0, len(get_all_ents()), allocator=context.temp_allocator)
		for handle in get_all_ents() {
			append(&draw_order, handle)
		}

		// Draw top-to-bottom using hitbox base Y so lower-footprint objects render in front.
		for i in 1..<len(draw_order) {
			key := draw_order[i]
			key_y := get_entity_sort_y(entity_from_handle(key)^)
			j := i

			for j > 0 {
				prev := entity_from_handle(draw_order[j-1])
				prev_y := get_entity_sort_y(prev^)
				if prev_y >= key_y do break
				draw_order[j] = draw_order[j-1]
				j -= 1
			}

			draw_order[j] = key
		}

		for handle in draw_order {
			e := entity_from_handle(handle)
			e.draw_proc(e^)
		}

		if ctx.gs.debug_show_hitboxes {
			draw_water_collision_debug()
			draw_terrain_block_collision_debug()
			for handle in get_all_ents() {
				e := entity_from_handle(handle)
				draw_entity_hitbox_debug(e^)
			}
		}

		if ctx.gs.debug_show_overlap_boxes {
			for handle in get_all_ents() {
				e := entity_from_handle(handle)
				draw_entity_overlap_debug(e^)
			}
		}

		if ctx.gs.debug_show_durability {
			for handle in get_all_ents() {
				e := entity_from_handle(handle)
				draw_entity_durability_debug(e^)
			}
		}
		if ctx.gs.debug_show_growth {
			for handle in get_all_ents() {
				e := entity_from_handle(handle)
				draw_entity_growth_debug(e^)
			}
		}

		draw_player_hit_cooldown_bar()
	}

	// HUD: FPS counter (smoothed enough by frame cadence for debug usage).
	{
		push_coord_space(get_screen_space())
		fps := 0
		if ctx.delta_t > 0 {
			fps = int(math.round(1.0 / ctx.delta_t))
		}
		draw_text(Vec2{6, f32(GAME_RES_HEIGHT) - 6}, fmt.tprintf("FPS: %v", fps), pivot=.top_left, z_layer=.ui, col=Vec4{1, 1, 1, 0.85}, drop_shadow_col=Vec4{0, 0, 0, 0.75}, scale=0.45)
	}
}

get_placeable_preview_sprite :: proc(item: Item_Kind) -> (sprite: Sprite_Name, ok: bool) {
	#partial switch item {
	case .sapling:
		return .sapling, true
	case:
		return .nil, false
	}
}

get_placeable_preview_pivot :: proc(item: Item_Kind) -> utils.Pivot {
	#partial switch item {
	case .sapling:
		return .bottom_center
	case:
		return .center_center
	}
}

draw_placeable_preview :: proc() {
	if is_any_ui_overlay_open() {
		return
	}

	player := get_player()
	if !is_valid(player^) {
		return
	}

	item, count := get_equipped_item()
	if count <= 0 {
		return
	}

	sprite, ok := get_placeable_preview_sprite(item)
	if !ok {
		return
	}

	place_pos := Vec2{}
	if player.has_pending_place && player.pending_place_item == item {
		// Lock preview to the original clicked target while auto-moving to place.
		place_pos = player.pending_place_pos
	} else {
		mouse_world := mouse_pos_in_current_space()
		_, hit_ok := find_hittable_entity_at_world_pos(mouse_world)
		if hit_ok {
			return
		}

		place_pos = snap_vec2_to_grid_center(mouse_world, ENTITY_GRID_SIZE)
		diff := place_pos - player.pos
		d2 := diff.x*diff.x + diff.y*diff.y
		if d2 > PLACE_PREVIEW_RANGE*PLACE_PREVIEW_RANGE {
			return
		}
	}

	col := Vec4{1, 1, 1, 0.35}
	if is_world_position_blocked_for_player(place_pos) {
		col = Vec4{1, 0.25, 0.25, 0.28}
	}
	draw_sprite(place_pos, sprite, pivot=get_placeable_preview_pivot(item), col=col, z_layer=.vfx)
}

floor_div_int :: proc(v: int, d: int) -> int {
	if d == 0 do return 0
	q := v / d
	r := v % d
	if r != 0 && ((r > 0) != (d > 0)) {
		q -= 1
	}
	return q
}

make_world_area_key :: proc(area_x: int, area_y: int) -> u64 {
	ux := u64(u32(area_x))
	uy := u64(u32(area_y))
	return (ux << 32) | uy
}

world_area_coords_from_key :: proc(key: u64) -> (int, int) {
	ax := int(i32((key >> 32) & 0xFFFF_FFFF))
	ay := int(i32(key & 0xFFFF_FFFF))
	return ax, ay
}

world_area_coord_for_tile :: proc(tile_coord: int) -> int {
	return floor_div_int(tile_coord, WORLD_UNLOCK_AREA_SIZE_TILES)
}

world_area_for_world_pos :: proc(pos: Vec2) -> (int, int) {
	tile_x := int(math.floor(pos.x / ENTITY_GRID_SIZE))
	tile_y := int(math.floor(pos.y / ENTITY_GRID_SIZE))
	return world_area_coord_for_tile(tile_x), world_area_coord_for_tile(tile_y)
}

is_world_area_unlocked :: proc(area_x: int, area_y: int) -> bool {
	key := make_world_area_key(area_x, area_y)
	for k in ctx.gs.unlocked_world_areas {
		if k == key {
			return true
		}
	}
	return false
}

unlock_world_area :: proc(area_x: int, area_y: int) -> bool {
	if is_world_area_unlocked(area_x, area_y) {
		return false
	}
	append(&ctx.gs.unlocked_world_areas, make_world_area_key(area_x, area_y))
	return true
}

unlock_world_area_for_world_pos :: proc(pos: Vec2) -> bool {
	ax, ay := world_area_for_world_pos(pos)
	return unlock_world_area(ax, ay)
}

unlock_world_area_with_adjacent :: proc(area_x: int, area_y: int) {
	for oy := -1; oy <= 1; oy += 1 {
		for ox := -1; ox <= 1; ox += 1 {
			_ = unlock_world_area(area_x+ox, area_y+oy)
		}
	}
}

is_tile_in_unlocked_world :: proc(tile_x: int, tile_y: int) -> bool {
	ax := world_area_coord_for_tile(tile_x)
	ay := world_area_coord_for_tile(tile_y)
	return is_world_area_unlocked(ax, ay)
}

is_world_pos_in_locked_area :: proc(pos: Vec2) -> bool {
	if len(ctx.gs.unlocked_world_areas) == 0 {
		return false
	}
	tile_x := int(math.floor(pos.x / ENTITY_GRID_SIZE))
	tile_y := int(math.floor(pos.y / ENTITY_GRID_SIZE))
	return !is_tile_in_unlocked_world(tile_x, tile_y)
}

is_rect_touching_locked_world_area :: proc(rect: shape.Rect) -> bool {
	if len(ctx.gs.unlocked_world_areas) == 0 {
		return false
	}
	min_tile_x := int(math.floor(rect.x / ENTITY_GRID_SIZE))
	max_tile_x := int(math.floor(rect.z / ENTITY_GRID_SIZE))
	min_tile_y := int(math.floor(rect.y / ENTITY_GRID_SIZE))
	max_tile_y := int(math.floor(rect.w / ENTITY_GRID_SIZE))

	for ty := min_tile_y; ty <= max_tile_y; ty += 1 {
		for tx := min_tile_x; tx <= max_tile_x; tx += 1 {
			if !is_tile_in_unlocked_world(tx, ty) {
				return true
			}
		}
	}
	return false
}

manual_spawn_origin_offset :: proc() -> Vec2 {
	half_tiles := f32(WORLD_UNLOCK_AREA_SIZE_TILES) * 0.5
	off := half_tiles * ENTITY_GRID_SIZE
	return Vec2{off, off}
}

is_spawn_hitbox_overlapping :: proc(rect: shape.Rect) -> bool {
	if is_rect_touching_locked_world_area(rect) || is_rect_touching_water_collision(rect) || is_rect_touching_terrain_block_collision(rect) {
		return true
	}

	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		hitbox, ok := get_entity_hitbox_rect(e^)
		if !ok {
			continue
		}
		hit, _ := rounded_hitbox_collide_rect(rect, hitbox, HITBOX_CORNER_CUT)
		if hit {
			return true
		}
	}
	return false
}

find_clear_manual_spawn_pos_for_hitbox :: proc(desired: Vec2, hitbox_size: Vec2, hitbox_pivot: utils.Pivot) -> Vec2 {
	if !is_spawn_hitbox_overlapping(shape.rect_make(desired, hitbox_size, pivot=hitbox_pivot)) {
		return desired
	}

	grid := ENTITY_GRID_SIZE
	max_radius_tiles := max(8, WORLD_UNLOCK_AREA_SIZE_TILES*2)
	for r := 1; r <= max_radius_tiles; r += 1 {
		found := false
		best := desired
		best_d2 := f32(1e30)

		for oy := -r; oy <= r; oy += 1 {
			for ox := -r; ox <= r; ox += 1 {
				if !(ox == -r || ox == r || oy == -r || oy == r) {
					continue
				}

				candidate := desired + Vec2{f32(ox) * grid, f32(oy) * grid}
				if is_spawn_hitbox_overlapping(shape.rect_make(candidate, hitbox_size, pivot=hitbox_pivot)) {
					continue
				}

				d := candidate - desired
				d2 := d.x*d.x + d.y*d.y
				if d2 < best_d2 {
					best_d2 = d2
					best = candidate
					found = true
				}
			}
		}

		if found {
			return best
		}
	}

	return desired
}

manual_spawn_world_pos_for_hitbox :: proc(pos: Vec2, hitbox_size: Vec2, hitbox_pivot: utils.Pivot) -> Vec2 {
	desired := pos + manual_spawn_origin_offset()
	return find_clear_manual_spawn_pos_for_hitbox(desired, hitbox_size, hitbox_pivot)
}

manual_spawn_world_pos :: proc(pos: Vec2) -> Vec2 {
	// Default to player-footprint spawn resolution for generic manual placements.
	return manual_spawn_world_pos_for_hitbox(pos, Vec2{8, 8}, .bottom_center)
}

is_chunk_in_unlocked_world :: proc(chunk_x: int, chunk_y: int) -> bool {
	min_tile_x := chunk_x * BIOME_CHUNK_SIZE_TILES
	max_tile_x := min_tile_x + BIOME_CHUNK_SIZE_TILES - 1
	min_tile_y := chunk_y * BIOME_CHUNK_SIZE_TILES
	max_tile_y := min_tile_y + BIOME_CHUNK_SIZE_TILES - 1

	area_min_x := world_area_coord_for_tile(min_tile_x)
	area_max_x := world_area_coord_for_tile(max_tile_x)
	area_min_y := world_area_coord_for_tile(min_tile_y)
	area_max_y := world_area_coord_for_tile(max_tile_y)

	for ay := area_min_y; ay <= area_max_y; ay += 1 {
		for ax := area_min_x; ax <= area_max_x; ax += 1 {
			if is_world_area_unlocked(ax, ay) {
				return true
			}
		}
	}
	return false
}

is_spawn_pos_blocked_for_player_ignore_locked :: proc(player: ^Entity, pos: Vec2) -> bool {
	probe := player^
	probe.pos = pos
	player_hitbox, ok := get_entity_hitbox_rect(probe)
	if !ok {
		return false
	}

	if is_rect_touching_water_collision(player_hitbox) || is_rect_touching_terrain_block_collision(player_hitbox) {
		return true
	}

	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !e.blocks_player do continue
		if e.handle.id == player.handle.id do continue

		blocker_hitbox, blocker_ok := get_entity_hitbox_rect(e^)
		if !blocker_ok do continue
		hit, _ := rounded_hitbox_collide_rect(player_hitbox, blocker_hitbox, HITBOX_CORNER_CUT)
		if hit {
			return true
		}
	}
	return false
}

find_player_spawn_pos_near_middle :: proc(player: ^Entity, desired_center: Vec2) -> Vec2 {
	if !is_spawn_pos_blocked_for_player_ignore_locked(player, desired_center) {
		return desired_center
	}

	grid := ENTITY_GRID_SIZE
	max_radius_tiles := max(8, WORLD_UNLOCK_AREA_SIZE_TILES*2)
	for r := 1; r <= max_radius_tiles; r += 1 {
		found := false
		best := desired_center
		best_d2 := f32(1e30)

		for oy := -r; oy <= r; oy += 1 {
			for ox := -r; ox <= r; ox += 1 {
				if !(ox == -r || ox == r || oy == -r || oy == r) {
					continue
				}

				candidate := desired_center + Vec2{f32(ox) * grid, f32(oy) * grid}
				if is_spawn_pos_blocked_for_player_ignore_locked(player, candidate) {
					continue
				}

				d := candidate - desired_center
				d2 := d.x*d.x + d.y*d.y
				if d2 < best_d2 {
					best_d2 = d2
					best = candidate
					found = true
				}
			}
		}

		if found {
			return best
		}
	}

	return desired_center
}

get_unlocked_world_tile_bounds :: proc() -> (min_tile_x: int, min_tile_y: int, max_tile_x: int, max_tile_y: int, ok: bool) {
	if len(ctx.gs.unlocked_world_areas) == 0 {
		return 0, 0, 0, 0, false
	}

	first := true
	for key in ctx.gs.unlocked_world_areas {
		ax, ay := world_area_coords_from_key(key)
		area_min_x := ax * WORLD_UNLOCK_AREA_SIZE_TILES
		area_min_y := ay * WORLD_UNLOCK_AREA_SIZE_TILES
		area_max_x := area_min_x + WORLD_UNLOCK_AREA_SIZE_TILES - 1
		area_max_y := area_min_y + WORLD_UNLOCK_AREA_SIZE_TILES - 1

		if first {
			min_tile_x = area_min_x
			min_tile_y = area_min_y
			max_tile_x = area_max_x
			max_tile_y = area_max_y
			first = false
		} else {
			if area_min_x < min_tile_x do min_tile_x = area_min_x
			if area_min_y < min_tile_y do min_tile_y = area_min_y
			if area_max_x > max_tile_x do max_tile_x = area_max_x
			if area_max_y > max_tile_y do max_tile_y = area_max_y
		}
	}
	return min_tile_x, min_tile_y, max_tile_x, max_tile_y, true
}

get_follow_camera_target :: proc(player_pos: Vec2) -> Vec2 {
	min_tx, min_ty, max_tx, max_ty, ok := get_unlocked_world_tile_bounds()
	if !ok {
		return player_pos
	}

	min_world := Vec2{f32(min_tx) * ENTITY_GRID_SIZE, f32(min_ty) * ENTITY_GRID_SIZE}
	max_world := Vec2{f32(max_tx+1) * ENTITY_GRID_SIZE, f32(max_ty+1) * ENTITY_GRID_SIZE}

	half_view_w := f32(GAME_RES_WIDTH) * 0.5
	half_view_h := f32(GAME_RES_HEIGHT) * 0.5
	margin_x := WORLD_UNLOCK_CAMERA_EDGE_MARGIN_TILES * ENTITY_GRID_SIZE
	margin_y: f32 = 0

	min_cam_x := min_world.x + half_view_w - margin_x
	max_cam_x := max_world.x - half_view_w + margin_x
	min_cam_y := min_world.y + half_view_h - margin_y
	max_cam_y := max_world.y - half_view_h + margin_y

	target := player_pos
	if min_cam_x > max_cam_x {
		target.x = (min_world.x + max_world.x) * 0.5
	} else {
		target.x = math.clamp(target.x, min_cam_x, max_cam_x)
	}
	if min_cam_y > max_cam_y {
		target.y = (min_world.y + max_world.y) * 0.5
	} else {
		target.y = math.clamp(target.y, min_cam_y, max_cam_y)
	}
	return target
}

sprite_is_loaded :: proc(sprite: Sprite_Name) -> bool {
	size := get_sprite_size(sprite)
	return size.x > 0 && size.y > 0
}

TERRAIN_TILESET_BLOCK_PX :: 64
TERRAIN_TILESET_BLOCKS_PER_ROW :: 9
TERRAIN_TILESET_BLOCK_ROWS :: 6
TERRAIN_DEFAULT_BLOCK_INDEX :: 11
TERRAIN_MAX_BLOCK_INDEX :: 54
WATER_COLLISION_OVERSIZE_PX: f32 : 6.0

clear_terrain_block_hitboxes :: proc() {
	for i in 0..=TERRAIN_MAX_BLOCK_INDEX {
		terrain_block_hitboxes[i] = {}
	}
}

clear_terrain_block_hitbox :: proc(block_index: int) {
	if block_index < 1 || block_index > TERRAIN_MAX_BLOCK_INDEX {
		return
	}
	terrain_block_hitboxes[block_index] = {}
}

add_terrain_block_hitbox :: proc(block_index: int, offset: Vec2, size: Vec2) {
	if block_index < 1 || block_index > TERRAIN_MAX_BLOCK_INDEX {
		return
	}

	if size.x <= 0 || size.y <= 0 {
		return
	}

	set := &terrain_block_hitboxes[block_index]
	if set.count >= len(set.boxes) {
		return
	}
	set.boxes[set.count] = Terrain_Block_Hitbox{offset = offset, size = size}
	set.count += 1
}

set_terrain_block_hitbox :: proc(block_index: int, offset: Vec2, size: Vec2) {
	clear_terrain_block_hitbox(block_index)
	add_terrain_block_hitbox(block_index, offset, size)
}

setup_terrain_block_hitboxes :: proc() {
	clear_terrain_block_hitboxes()

	// Flat ground: no collision.
	set_terrain_block_hitbox(1, Vec2{0, 32}, Vec2{32,2})
	add_terrain_block_hitbox(1, Vec2{0, 0}, Vec2{2,32})
	set_terrain_block_hitbox(2, Vec2{0, 32}, Vec2{32,2})
	set_terrain_block_hitbox(3, Vec2{0, 32}, Vec2{32,2})
	add_terrain_block_hitbox(3, Vec2{32, 0}, Vec2{2,32})
	set_terrain_block_hitbox(10, Vec2{0, 0}, Vec2{2,32})
	set_terrain_block_hitbox(11, {}, {})
	set_terrain_block_hitbox(12, Vec2{32, 0}, Vec2{2,32})
	set_terrain_block_hitbox(19, Vec2{0, 0}, Vec2{32,2})
	add_terrain_block_hitbox(19, Vec2{0, 0}, Vec2{2,32})
	set_terrain_block_hitbox(20, Vec2{0, 0}, Vec2{32,2})
	set_terrain_block_hitbox(21, Vec2{0, 0}, Vec2{32,2})
	add_terrain_block_hitbox(21, Vec2{32, 0}, Vec2{2,32})

	// Default blocking examples for cliff/wall row in the Tiny Swords 9x6 layout.
	// Edit these definitions per block index to match your intended terrain collision.
	for block in 46..=54 {
		set_terrain_block_hitbox(block, Vec2{0, 0}, Vec2{ENTITY_GRID_SIZE, ENTITY_GRID_SIZE})
	}
}
positive_mod_int :: proc(v: int, m: int) -> int {
	if m <= 0 do return 0
	r := v % m
	if r < 0 {
		r += m
	}
	return r
}

find_terrain_structure_index_by_name :: proc(name: string) -> (int, bool) {
	if len(terrain_structures) == 0 {
		return -1, false
	}
	id, id_ok := parse_positive_int_str(name)
	if id_ok {
		idx := id - 1
		if idx >= 0 && idx < len(terrain_structures) {
			return idx, true
		}
	}

	for i in 0..<len(terrain_structures) {
		if terrain_structures[i].name == name {
			return i, true
		}
	}
	return -1, false
}

spawn_terrain_structure_at_tile :: proc(name: string, origin_tile_x: int, origin_tile_y: int) -> bool {
	structure_index, ok := find_terrain_structure_index_by_name(name)
	if !ok {
		log.warnf("spawn_terrain_structure: unknown structure %q (loaded=%v)", name, len(terrain_structures))
		return false
	}

	append(&ctx.gs.terrain_structure_instances, Terrain_Structure_Instance{
		structure_index = structure_index,
		origin_tile_x = origin_tile_x,
		origin_tile_y = origin_tile_y,
	})
	return true
}

spawn_terrain_structure :: proc(name: string, world_pos: Vec2) -> bool {
	spawn_pos := manual_spawn_world_pos(world_pos)
	origin_tile_x := int(math.floor(spawn_pos.x / ENTITY_GRID_SIZE))
	origin_tile_y := int(math.floor(spawn_pos.y / ENTITY_GRID_SIZE))
	return spawn_terrain_structure_at_tile(name, origin_tile_x, origin_tile_y)
}

terrain_tile_for_tile :: proc(tile_x: int, tile_y: int) -> Terrain_Tile {
	// Later-spawned structures take priority where they overlap.
	for i := len(ctx.gs.terrain_structure_instances) - 1; i >= 0; i -= 1 {
		inst := ctx.gs.terrain_structure_instances[i]
		if inst.structure_index < 0 || inst.structure_index >= len(terrain_structures) {
			continue
		}

		st := terrain_structures[inst.structure_index]
		if st.cols <= 0 || st.rows <= 0 {
			continue
		}

		rel_x := tile_x - inst.origin_tile_x
		// Structures are indexed top->bottom, left->right from origin.
		rel_y := inst.origin_tile_y - tile_y
		if rel_x < 0 || rel_y < 0 || rel_x >= st.cols || rel_y >= st.rows {
			continue
		}

		return st.tiles[rel_y][rel_x]
	}
	return Terrain_Tile{kind=.block, block_index=TERRAIN_DEFAULT_BLOCK_INDEX}
}

terrain_block_index_for_tile :: proc(tile_x: int, tile_y: int) -> int {
	tile := terrain_tile_for_tile(tile_x, tile_y)
	if tile.kind == .block {
		return tile.block_index
	}
	return 0
}

is_terrain_solid_tile :: proc(tile_x: int, tile_y: int) -> bool {
	tile := terrain_tile_for_tile(tile_x, tile_y)
	return tile.kind == .block && tile.block_index > 0
}

terrain_block_hitbox_count_for_tile :: proc(tile_x: int, tile_y: int) -> int {
	tile := terrain_tile_for_tile(tile_x, tile_y)
	if tile.kind != .block || tile.block_index <= 0 || tile.block_index > TERRAIN_MAX_BLOCK_INDEX {
		return 0
	}

	set := terrain_block_hitboxes[tile.block_index]
	return set.count
}

terrain_block_hitbox_rect_for_tile :: proc(tile_x: int, tile_y: int, hitbox_index: int) -> (shape.Rect, bool) {
	tile := terrain_tile_for_tile(tile_x, tile_y)
	if tile.kind != .block || tile.block_index <= 0 || tile.block_index > TERRAIN_MAX_BLOCK_INDEX {
		return {}, false
	}

	set := terrain_block_hitboxes[tile.block_index]
	if hitbox_index < 0 || hitbox_index >= set.count || hitbox_index >= len(set.boxes) {
		return {}, false
	}

	cfg := set.boxes[hitbox_index]
	if cfg.size.x <= 0 || cfg.size.y <= 0 {
		return {}, false
	}

	tile_min := Vec2{f32(tile_x) * ENTITY_GRID_SIZE, f32(tile_y) * ENTITY_GRID_SIZE}
	rect := shape.Rect{
		tile_min.x + cfg.offset.x,
		tile_min.y + cfg.offset.y,
		tile_min.x + cfg.offset.x + cfg.size.x,
		tile_min.y + cfg.offset.y + cfg.size.y,
	}
	return rect, true
}

is_world_pos_in_terrain_block_collision :: proc(pos: Vec2) -> bool {
	tile_x := int(math.floor(pos.x / ENTITY_GRID_SIZE))
	tile_y := int(math.floor(pos.y / ENTITY_GRID_SIZE))
	for oy := -1; oy <= 1; oy += 1 {
		for ox := -1; ox <= 1; ox += 1 {
			tx := tile_x + ox
			ty := tile_y + oy
			count := terrain_block_hitbox_count_for_tile(tx, ty)
			for i in 0..<count {
				rect, ok := terrain_block_hitbox_rect_for_tile(tx, ty, i)
				if ok && shape.rect_contains(rect, pos) {
					return true
				}
			}
		}
	}
	return false
}

is_water_pixel_blocked :: proc(tile_x: int, tile_y: int, world_pos: Vec2) -> bool {
	tile := terrain_tile_for_tile(tile_x, tile_y)
	if tile.kind != .water {
		return false
	}

	grid := ENTITY_GRID_SIZE
	if grid <= 0 {
		return false
	}

	mask := water_mask_for_variant(tile.water_variant)

	// Fallback if mask is missing: water tile is fully blocked.
	if mask.width <= 0 || mask.height <= 0 || len(mask.alpha) == 0 {
		return true
	}

	tile_min_x := f32(tile_x) * grid
	tile_min_y := f32(tile_y) * grid
	u := math.clamp((world_pos.x-tile_min_x)/grid, 0, 0.9999)
	v := math.clamp((world_pos.y-tile_min_y)/grid, 0, 0.9999)
	if tile.water_flip_x {
		u = 1.0 - u
	}

	px := clamp(int(math.floor(u * f32(mask.width))), 0, mask.width-1)
	py := clamp(int(math.floor(v * f32(mask.height))), 0, mask.height-1)
	idx := py*mask.width + px
	if idx < 0 || idx >= len(mask.alpha) {
		return true
	}

	return mask.alpha[idx] > 0
}

is_water_pixel_blocked_oversized :: proc(tile_x: int, tile_y: int, world_pos: Vec2, oversize_px: f32) -> bool {
	grid := ENTITY_GRID_SIZE
	if grid <= 0 {
		return false
	}

	tile_min_x := f32(tile_x) * grid
	tile_min_y := f32(tile_y) * grid
	tile_rect := shape.Rect{
		tile_min_x - oversize_px,
		tile_min_y - oversize_px,
		tile_min_x + grid + oversize_px,
		tile_min_y + grid + oversize_px,
	}
	if !shape.rect_contains(tile_rect, world_pos) {
		return false
	}
	return is_water_pixel_blocked(tile_x, tile_y, world_pos)
}

is_world_pos_in_water_collision :: proc(pos: Vec2) -> bool {
	tile_x := int(math.floor(pos.x / ENTITY_GRID_SIZE))
	tile_y := int(math.floor(pos.y / ENTITY_GRID_SIZE))
	oversize := max(0.0, WATER_COLLISION_OVERSIZE_PX)
	for oy := -1; oy <= 1; oy += 1 {
		for ox := -1; ox <= 1; ox += 1 {
			if is_water_pixel_blocked_oversized(tile_x+ox, tile_y+oy, pos, oversize) {
				return true
			}
		}
	}
	return false
}

is_rect_touching_water_collision :: proc(rect: shape.Rect) -> bool {
	step: f32 = 1.0
	y := rect.y
	for y <= rect.w {
		x := rect.x
		for x <= rect.z {
			if is_world_pos_in_water_collision(Vec2{x, y}) {
				return true
			}
			x += step
		}
		y += step
	}
	return false
}

is_rect_touching_terrain_block_collision :: proc(rect: shape.Rect) -> bool {
	min_tile_x := int(math.floor(rect.x / ENTITY_GRID_SIZE)) - 1
	max_tile_x := int(math.floor(rect.z / ENTITY_GRID_SIZE)) + 1
	min_tile_y := int(math.floor(rect.y / ENTITY_GRID_SIZE)) - 1
	max_tile_y := int(math.floor(rect.w / ENTITY_GRID_SIZE)) + 1

	ty := min_tile_y
	for ty <= max_tile_y {
		tx := min_tile_x
		for tx <= max_tile_x {
			count := terrain_block_hitbox_count_for_tile(tx, ty)
			for i in 0..<count {
				block_rect, block_ok := terrain_block_hitbox_rect_for_tile(tx, ty, i)
				if block_ok {
					hit, _ := rounded_hitbox_collide_rect(rect, block_rect, HITBOX_CORNER_CUT)
					if hit {
						return true
					}
				}
			}
			tx += 1
		}
		ty += 1
	}
	return false
}

draw_water_collision_debug :: proc() {
	tile_size := Vec2{ENTITY_GRID_SIZE, ENTITY_GRID_SIZE}
	center := ctx.gs.cam_pos
	half_w := f32(GAME_RES_WIDTH)*0.5 + tile_size.x
	half_h := f32(GAME_RES_HEIGHT)*0.5 + tile_size.y

	min_tile_x := int(math.floor((center.x - half_w) / tile_size.x))
	max_tile_x := int(math.ceil((center.x + half_w) / tile_size.x))
	min_tile_y := int(math.floor((center.y - half_h) / tile_size.y))
	max_tile_y := int(math.ceil((center.y + half_h) / tile_size.y))
	ty := min_tile_y
	layer: ZLayer = .top
	if is_game_paused() {
		layer = .pause_menu
	}
	for ty <= max_tile_y {
		tx := min_tile_x
		for tx <= max_tile_x {
			tile := terrain_tile_for_tile(tx, ty)
			if tile.kind != .water {
				tx += 1
				continue
			}

			mask := water_mask_for_variant(tile.water_variant)
			mask_w := mask.width
			mask_h := mask.height
			has_mask := mask_w > 0 && mask_h > 0 && len(mask.alpha) >= mask_w*mask_h
			opaque_min_x := mask_w
			opaque_min_y := mask_h
			opaque_max_x := -1
			opaque_max_y := -1
			if has_mask {
				for py in 0..<mask_h {
					for px in 0..<mask_w {
						idx := py*mask_w + px
						if mask.alpha[idx] == 0 do continue
						if px < opaque_min_x do opaque_min_x = px
						if py < opaque_min_y do opaque_min_y = py
						if px > opaque_max_x do opaque_max_x = px
						if py > opaque_max_y do opaque_max_y = py
					}
				}
				if opaque_max_x < opaque_min_x || opaque_max_y < opaque_min_y {
					has_mask = false
				}
			}

			tile_min_x := f32(tx) * ENTITY_GRID_SIZE
			tile_min_y := f32(ty) * ENTITY_GRID_SIZE
			oversize := max(0.0, WATER_COLLISION_OVERSIZE_PX)

			debug_rect: shape.Rect
			if has_mask {
				u0 := f32(opaque_min_x) / f32(mask_w)
				v0 := f32(opaque_min_y) / f32(mask_h)
				u1 := f32(opaque_max_x+1) / f32(mask_w)
				v1 := f32(opaque_max_y+1) / f32(mask_h)
				debug_rect = shape.Rect{
					tile_min_x + u0*ENTITY_GRID_SIZE - oversize,
					tile_min_y + v0*ENTITY_GRID_SIZE - oversize,
					tile_min_x + u1*ENTITY_GRID_SIZE + oversize,
					tile_min_y + v1*ENTITY_GRID_SIZE + oversize,
				}
			} else {
				debug_rect = shape.Rect{
					tile_min_x - oversize,
					tile_min_y - oversize,
					tile_min_x + ENTITY_GRID_SIZE + oversize,
					tile_min_y + ENTITY_GRID_SIZE + oversize,
				}
			}

			draw_rect(debug_rect, col=Vec4{0.2, 0.75, 1.0, 0.12}, outline_col=Vec4{0.2, 0.75, 1.0, 0.82}, z_layer=layer)
			tx += 1
		}
		ty += 1
	}
}

draw_terrain_block_collision_debug :: proc() {
	tile_size := Vec2{ENTITY_GRID_SIZE, ENTITY_GRID_SIZE}
	center := ctx.gs.cam_pos
	half_w := f32(GAME_RES_WIDTH)*0.5 + tile_size.x
	half_h := f32(GAME_RES_HEIGHT)*0.5 + tile_size.y

	min_tile_x := int(math.floor((center.x - half_w) / tile_size.x))
	max_tile_x := int(math.ceil((center.x + half_w) / tile_size.x))
	min_tile_y := int(math.floor((center.y - half_h) / tile_size.y))
	max_tile_y := int(math.ceil((center.y + half_h) / tile_size.y))

	ty := min_tile_y
	layer: ZLayer = .top
	if is_game_paused() {
		layer = .pause_menu
	}
	for ty <= max_tile_y {
		tx := min_tile_x
		for tx <= max_tile_x {
			count := terrain_block_hitbox_count_for_tile(tx, ty)
			for i in 0..<count {
				rect, ok := terrain_block_hitbox_rect_for_tile(tx, ty, i)
				if ok {
					draw_rect(rect, col=Vec4{0, 0, 0, 0}, outline_col=Vec4{1.0, 0.62, 0.2, 0.88}, z_layer=layer)
				}
			}
			tx += 1
		}
		ty += 1
	}
}

draw_tileset_block_in_world_rect :: proc(sprite: Sprite_Name, block_index: int, world_rect: shape.Rect, col:=color.WHITE) {
	size := get_sprite_size(sprite)
	if size.x <= 0 || size.y <= 0 {
		return
	}
	if block_index < 1 || block_index > TERRAIN_MAX_BLOCK_INDEX {
		return
	}

	cell := block_index - 1
	cell_x := cell % TERRAIN_TILESET_BLOCKS_PER_ROW
	cell_y := cell / TERRAIN_TILESET_BLOCKS_PER_ROW
	cell_y = (TERRAIN_TILESET_BLOCK_ROWS - 1) - cell_y

	base_uv := atlas_uv_from_sprite(sprite)
	uv_w := base_uv.z - base_uv.x
	uv_h := base_uv.w - base_uv.y

	u0 := base_uv.x + (f32(cell_x*TERRAIN_TILESET_BLOCK_PX)/size.x) * uv_w
	v0 := base_uv.y + (f32(cell_y*TERRAIN_TILESET_BLOCK_PX)/size.y) * uv_h
	u1 := base_uv.x + (f32((cell_x+1)*TERRAIN_TILESET_BLOCK_PX)/size.x) * uv_w
	v1 := base_uv.y + (f32((cell_y+1)*TERRAIN_TILESET_BLOCK_PX)/size.y) * uv_h

	draw_rect(world_rect, sprite=sprite, uv=Vec4{u0, v0, u1, v1}, col=col)
}

make_chunk_key :: proc(chunk_x: int, chunk_y: int) -> u64 {
	ux := u64(u32(chunk_x))
	uy := u64(u32(chunk_y))
	return (ux << 32) | uy
}

is_vegetation_chunk_spawned :: proc(chunk_x: int, chunk_y: int) -> bool {
	key := make_chunk_key(chunk_x, chunk_y)
	for k in ctx.gs.spawned_vegetation_chunks {
		if k == key {
			return true
		}
	}
	return false
}

mark_vegetation_chunk_spawned :: proc(chunk_x: int, chunk_y: int) {
	append(&ctx.gs.spawned_vegetation_chunks, make_chunk_key(chunk_x, chunk_y))
}

can_spawn_entity_now :: proc() -> bool {
	return len(ctx.gs.entity_free_list) > 0 || ctx.gs.entity_top_count+1 < MAX_ENTITIES
}

is_spawn_position_clear :: proc(pos: Vec2, min_dist: f32) -> bool {
	min_dist_sq := min_dist * min_dist
	for &e in ctx.gs.entities {
		if !is_valid(e) do continue
		diff := e.pos - pos
		if diff.x*diff.x+diff.y*diff.y < min_dist_sq {
			return false
		}
	}
	return true
}

try_spawn_world_entity :: proc(kind: Entity_Kind, pos: Vec2, min_dist: f32) -> bool {
	if !can_spawn_entity_now() {
		return false
	}
	if !is_spawn_position_clear(pos, min_dist) {
		return false
	}

	e := entity_create(kind)
	e.pos = pos
	return true
}

spawn_grass_for_chunk :: proc(chunk_x: int, chunk_y: int, tile_size: Vec2) {
	chunk_world_min := Vec2{f32(chunk_x * BIOME_CHUNK_SIZE_TILES) * tile_size.x, f32(chunk_y * BIOME_CHUNK_SIZE_TILES) * tile_size.y}
	chunk_world_size := Vec2{f32(BIOME_CHUNK_SIZE_TILES) * tile_size.x, f32(BIOME_CHUNK_SIZE_TILES) * tile_size.y}

	spawned := 0
	for i in 0..<GRASS_SPAWN_TRIES_PER_CHUNK {
		if spawned >= GRASS_SPAWNS_PER_CHUNK do break

		base_seed := u64(i64(chunk_x)*73856093 + i64(chunk_y)*19349663 + i64(i)*83492791)
		rx := random01_from_seed(base_seed ~ 0x27D4EB2D)
		ry := random01_from_seed(base_seed ~ 0x85EBCA77)
		pos := chunk_world_min + Vec2{rx * chunk_world_size.x, ry * chunk_world_size.y}
		tile_x := int(math.floor(pos.x / tile_size.x))
		tile_y := int(math.floor(pos.y / tile_size.y))
		if !is_terrain_solid_tile(tile_x, tile_y) do continue

		if try_spawn_world_entity(.grass_ent, pos, VEG_MIN_DIST_GRASS) {
			spawned += 1
		}
	}
}

spawn_trees_for_chunk :: proc(chunk_x: int, chunk_y: int, tile_size: Vec2) {
	chunk_world_min := Vec2{f32(chunk_x * BIOME_CHUNK_SIZE_TILES) * tile_size.x, f32(chunk_y * BIOME_CHUNK_SIZE_TILES) * tile_size.y}
	chunk_world_size := Vec2{f32(BIOME_CHUNK_SIZE_TILES) * tile_size.x, f32(BIOME_CHUNK_SIZE_TILES) * tile_size.y}

	spawned := 0
	for i in 0..<TREE_SPAWN_TRIES_PER_CHUNK {
		if spawned >= TREE_SPAWNS_PER_CHUNK do break

		base_seed := u64(i64(chunk_x)*116129781 + i64(chunk_y)*961748927 + i64(i)*31337)
		rx := random01_from_seed(base_seed ~ 0x9E3779B9)
		ry := random01_from_seed(base_seed ~ 0x7F4A7C15)
		pos := chunk_world_min + Vec2{rx * chunk_world_size.x, ry * chunk_world_size.y}
		pos = snap_vec2_to_grid(pos, ENTITY_GRID_SIZE)
		tile_x := int(math.floor(pos.x / tile_size.x))
		tile_y := int(math.floor(pos.y / tile_size.y))
		if !is_terrain_solid_tile(tile_x, tile_y) do continue

		if try_spawn_world_entity(.tree_ent, pos, VEG_MIN_DIST_TREE) {
			spawned += 1
		}
	}
}

structure_overlaps_player_hitbox :: proc(st: Terrain_Structure, origin_tile_x: int, origin_tile_y: int, player_hitbox: shape.Rect) -> bool {
	for r in 0..<st.rows {
		for c in 0..<st.cols {
			tile := st.tiles[r][c]
			if tile.kind == .empty {
				continue
			}

			tile_x := origin_tile_x + c
			tile_y := origin_tile_y - r

			if tile.kind == .water {
				// Conservative trap-prevention: treat water structure tiles as blocking area for spawn overlap checks.
				tile_center := Vec2{(f32(tile_x) + 0.5) * ENTITY_GRID_SIZE, (f32(tile_y) + 0.5) * ENTITY_GRID_SIZE}
				tile_rect := shape.rect_make(tile_center, Vec2{ENTITY_GRID_SIZE, ENTITY_GRID_SIZE}, pivot=.center_center)
				hit, _ := rounded_hitbox_collide_rect(player_hitbox, tile_rect, HITBOX_CORNER_CUT)
				if hit {
					return true
				}
				continue
			}

			if tile.kind == .block && tile.block_index > 0 && tile.block_index <= TERRAIN_MAX_BLOCK_INDEX {
				set := terrain_block_hitboxes[tile.block_index]
				for i in 0..<set.count {
					cfg := set.boxes[i]
					if cfg.size.x <= 0 || cfg.size.y <= 0 {
						continue
					}
					tile_min := Vec2{f32(tile_x) * ENTITY_GRID_SIZE, f32(tile_y) * ENTITY_GRID_SIZE}
					block_rect := shape.Rect{
						tile_min.x + cfg.offset.x,
						tile_min.y + cfg.offset.y,
						tile_min.x + cfg.offset.x + cfg.size.x,
						tile_min.y + cfg.offset.y + cfg.size.y,
					}
					hit, _ := rounded_hitbox_collide_rect(player_hitbox, block_rect, HITBOX_CORNER_CUT)
					if hit {
						return true
					}
				}
			}
		}
	}
	return false
}

spawn_random_structure_for_chunk :: proc(chunk_x: int, chunk_y: int) {
	if len(terrain_structures) <= 0 {
		return
	}

	inner := STRUCTURE_CHUNK_INNER_AREA_TILES
	if inner <= 0 || inner > BIOME_CHUNK_SIZE_TILES {
		return
	}
	chunk_min_x := chunk_x * BIOME_CHUNK_SIZE_TILES
	chunk_max_x := chunk_min_x + BIOME_CHUNK_SIZE_TILES - 1
	chunk_min_y := chunk_y * BIOME_CHUNK_SIZE_TILES
	chunk_max_y := chunk_min_y + BIOME_CHUNK_SIZE_TILES - 1

	candidates := make([dynamic]int, 0, len(terrain_structures), allocator=context.temp_allocator)
	for i in 0..<len(terrain_structures) {
		st := terrain_structures[i]
		if st.cols <= 0 || st.rows <= 0 do continue
		if st.cols > inner || st.rows > inner do continue
		append(&candidates, i)
	}

	if len(candidates) == 0 {
		return
	}

	Inner_Zone :: struct {
		min_x, min_y, max_x, max_y: int,
	}
	zones := make([dynamic]Inner_Zone, 0, 16, allocator=context.temp_allocator)
	area_min_x := world_area_coord_for_tile(chunk_min_x)
	area_max_x := world_area_coord_for_tile(chunk_max_x)
	area_min_y := world_area_coord_for_tile(chunk_min_y)
	area_max_y := world_area_coord_for_tile(chunk_max_y)
	for ay := area_min_y; ay <= area_max_y; ay += 1 {
		for ax := area_min_x; ax <= area_max_x; ax += 1 {
			if !is_world_area_unlocked(ax, ay) {
				continue
			}

			area_tile_min_x := ax * WORLD_UNLOCK_AREA_SIZE_TILES
			area_tile_max_x := area_tile_min_x + WORLD_UNLOCK_AREA_SIZE_TILES - 1
			area_tile_min_y := ay * WORLD_UNLOCK_AREA_SIZE_TILES
			area_tile_max_y := area_tile_min_y + WORLD_UNLOCK_AREA_SIZE_TILES - 1

			inter_min_x := max(chunk_min_x, area_tile_min_x)
			inter_max_x := min(chunk_max_x, area_tile_max_x)
			inter_min_y := max(chunk_min_y, area_tile_min_y)
			inter_max_y := min(chunk_max_y, area_tile_max_y)
			if inter_max_x-inter_min_x+1 < inner || inter_max_y-inter_min_y+1 < inner {
				continue
			}

			append(&zones, Inner_Zone{inter_min_x, inter_min_y, inter_max_x, inter_max_y})
		}
	}

	if len(zones) == 0 {
		return
	}

	player := get_player()
	player_hitbox: shape.Rect
	player_hitbox_ok := false
	if is_valid(player^) {
		player_hitbox, player_hitbox_ok = get_entity_hitbox_rect(player^)
	}

	base_seed := u64(i64(chunk_x)*104729 + i64(chunk_y)*130363)
	for attempt := 0; attempt < 16; attempt += 1 {
		attempt_seed := base_seed + u64(attempt)*0x9E3779B97F4A7C15

		zone_f := random01_from_seed(attempt_seed ~ 0x243F6A8885A308D3)
		zone_i := clamp(int(math.floor(zone_f * f32(len(zones)))), 0, len(zones)-1)
		zone := zones[zone_i]

		zone_w := zone.max_x - zone.min_x + 1
		zone_h := zone.max_y - zone.min_y + 1
		inner_off_x_choices := zone_w - inner + 1
		inner_off_y_choices := zone_h - inner + 1
		inner_off_x := 0
		inner_off_y := 0
		if inner_off_x_choices > 1 {
			fx := random01_from_seed(attempt_seed ~ 0x13198A2E03707344)
			inner_off_x = clamp(int(math.floor(fx * f32(inner_off_x_choices))), 0, inner_off_x_choices-1)
		}
		if inner_off_y_choices > 1 {
			fy := random01_from_seed(attempt_seed ~ 0xA4093822299F31D0)
			inner_off_y = clamp(int(math.floor(fy * f32(inner_off_y_choices))), 0, inner_off_y_choices-1)
		}

		inner_min_x := zone.min_x + inner_off_x
		inner_min_y := zone.min_y + inner_off_y
		inner_max_x := inner_min_x + inner - 1
		inner_max_y := inner_min_y + inner - 1

		pick_f := random01_from_seed(attempt_seed ~ 0x9E3779B97F4A7C15)
		st_pick_i := clamp(int(math.floor(pick_f * f32(len(candidates)))), 0, len(candidates)-1)
		st_i := candidates[st_pick_i]
		st := terrain_structures[st_i]

		max_origin_x := inner_max_x - (st.cols - 1)
		min_origin_y := inner_min_y + (st.rows - 1)
		if max_origin_x < inner_min_x || min_origin_y > inner_max_y {
			continue
		}

		x_choices := max_origin_x - inner_min_x + 1
		y_choices := inner_max_y - min_origin_y + 1
		if x_choices <= 0 || y_choices <= 0 {
			continue
		}

		rx := random01_from_seed(attempt_seed ~ 0xD1B54A32D192ED03)
		ry := random01_from_seed(attempt_seed ~ 0x94D049BB133111EB)
		off_x := clamp(int(math.floor(rx * f32(x_choices))), 0, x_choices-1)
		off_y := clamp(int(math.floor(ry * f32(y_choices))), 0, y_choices-1)

		origin_tile_x := inner_min_x + off_x
		origin_tile_y := min_origin_y + off_y

		if player_hitbox_ok && structure_overlaps_player_hitbox(st, origin_tile_x, origin_tile_y, player_hitbox) {
			continue
		}

		append(&ctx.gs.terrain_structure_instances, Terrain_Structure_Instance{
			structure_index = st_i,
			origin_tile_x = origin_tile_x,
			origin_tile_y = origin_tile_y,
		})
		return
	}
}

spawn_vegetation_chunk :: proc(chunk_x: int, chunk_y: int, tile_size: Vec2) {
	if is_vegetation_chunk_spawned(chunk_x, chunk_y) {
		return
	}
	if !is_chunk_in_unlocked_world(chunk_x, chunk_y) {
		return
	}
	mark_vegetation_chunk_spawned(chunk_x, chunk_y)

	spawn_random_structure_for_chunk(chunk_x, chunk_y)
	spawn_grass_for_chunk(chunk_x, chunk_y, tile_size)
	spawn_trees_for_chunk(chunk_x, chunk_y, tile_size)
}

spawn_vegetation_near_player_chunks :: proc() {
	player := get_player()
	if !is_valid(player^) {
		return
	}

	tile_size := Vec2{ENTITY_GRID_SIZE, ENTITY_GRID_SIZE}

	player_tile_x := int(math.floor(player.pos.x / tile_size.x))
	player_tile_y := int(math.floor(player.pos.y / tile_size.y))
	player_chunk_x := floor_div_int(player_tile_x, BIOME_CHUNK_SIZE_TILES)
	player_chunk_y := floor_div_int(player_tile_y, BIOME_CHUNK_SIZE_TILES)

	cy := player_chunk_y - VEG_SPAWN_RADIUS_CHUNKS
	for cy <= player_chunk_y+VEG_SPAWN_RADIUS_CHUNKS {
		cx := player_chunk_x - VEG_SPAWN_RADIUS_CHUNKS
		for cx <= player_chunk_x+VEG_SPAWN_RADIUS_CHUNKS {
			spawn_vegetation_chunk(cx, cy, tile_size)
			cx += 1
		}
		cy += 1
	}
}

draw_placeable_range_circle :: proc() {
	if is_any_ui_overlay_open() {
		return
	}

	player := get_player()
	if !is_valid(player^) {
		return
	}

	item, count := get_equipped_item()
	if count <= 0 {
		return
	}
	_, ok := get_placeable_preview_sprite(item)
	if !ok {
		return
	}

	segments := 72
	step := f32(2.0 * math.PI) / f32(segments)
	for i in 0..<segments {
		a := f32(i) * step
		p := player.pos + Vec2{math.cos(a), math.sin(a)} * PLACE_PREVIEW_RANGE
		dot := shape.rect_make(p, Vec2{1, 1}, pivot=.center_center)
		draw_rect(dot, col=Vec4{1, 1, 1, 0.17}, z_layer=.shadow)
	}
}

draw_world_terrain_tiles :: proc() {
	tile_size := Vec2{ENTITY_GRID_SIZE, ENTITY_GRID_SIZE}

	center := ctx.gs.cam_pos
	half_w := f32(GAME_RES_WIDTH)*0.5 + tile_size.x
	half_h := f32(GAME_RES_HEIGHT)*0.5 + tile_size.y

	min_tile_x := int(math.floor((center.x - half_w) / tile_size.x))
	max_tile_x := int(math.ceil((center.x + half_w) / tile_size.x))
	min_tile_y := int(math.floor((center.y - half_h) / tile_size.y))
	max_tile_y := int(math.ceil((center.y + half_h) / tile_size.y))

	ty := min_tile_y
	for ty <= max_tile_y {
		tx := min_tile_x
		for tx <= max_tile_x {
			if !is_tile_in_unlocked_world(tx, ty) {
				tile_center := Vec2{(f32(tx) + 0.5) * tile_size.x, (f32(ty) + 0.5) * tile_size.y}
				tile_rect := shape.rect_make(tile_center, tile_size, pivot=.center_center)
				draw_rect(tile_rect, col=Vec4{0.01, 0.01, 0.01, 0.96})
				tx += 1
				continue
			}

			tile := terrain_tile_for_tile(tx, ty)
			tile_center := Vec2{(f32(tx) + 0.5) * tile_size.x, (f32(ty) + 0.5) * tile_size.y}
			tile_rect := shape.rect_make(tile_center, tile_size, pivot=.center_center)
			water_sprite := water_sprite_for_variant(tile.water_variant)
			if !sprite_is_loaded(water_sprite) {
				water_sprite = water_sprite_for_variant(1)
			}
			// Water underlay for non-water tiles so transparent pixels reveal water below.
			if tile.kind != .water {
				if sprite_is_loaded(water_sprite) {
					draw_terrain_water_tile_sprite(water_sprite, tile_center, tile_size, tile.water_flip_x)
				} else {
					draw_rect(tile_rect, col=Vec4{0.18, 0.35, 0.72, 1.0})
				}
			} else {
				draw_rect(tile_rect, col=Vec4{0.18, 0.35, 0.72, 1.0})
			}

			if tile.kind == .water {
				if sprite_is_loaded(water_sprite) {
					draw_terrain_water_tile_sprite(water_sprite, tile_center, tile_size, tile.water_flip_x)
				}
			} else if tile.kind == .block {
				if sprite_is_loaded(.tilemap_color1) {
					draw_tileset_block_in_world_rect(.tilemap_color1, tile.block_index, tile_rect, col=Vec4{1, 1, 1, 0.95})
				}
			}
			if ctx.gs.debug_show_grid {
				label := tile.kind == .water ? fmt.tprintf("w%v%v", clamp(tile.water_variant, 1, MAX_WATER_VARIANTS), tile.water_flip_x ? "a" : "") : fmt.tprintf("%v", tile.block_index)
				draw_text(tile_center, label, pivot=.center_center, z_layer=.top, col=Vec4{1, 1, 1, 0.85}, drop_shadow_col=Vec4{0, 0, 0, 0.8}, scale=0.35)
			}
			tx += 1
		}
		ty += 1
	}
}

draw_world_grid :: proc() {
	grid := ENTITY_GRID_SIZE
	if grid <= 0 {
		return
	}

	center := ctx.gs.cam_pos
	half_w := f32(GAME_RES_WIDTH)*0.5 + grid
	half_h := f32(GAME_RES_HEIGHT)*0.5 + grid

	min_x := snap_to_grid(center.x-half_w, grid)
	max_x := snap_to_grid(center.x+half_w, grid)
	min_y := snap_to_grid(center.y-half_h, grid)
	max_y := snap_to_grid(center.y+half_h, grid)

	x := min_x
	for x <= max_x {
		line := shape.rect_make(Vec2{x, (min_y + max_y) * 0.5}, Vec2{1, max_y-min_y+grid}, pivot=.center_center)
		draw_rect(line, col=Vec4{1, 1, 1, 0.08}, z_layer=.shadow)
		x += grid
	}

	y := min_y
	for y <= max_y {
		line := shape.rect_make(Vec2{(min_x + max_x) * 0.5, y}, Vec2{max_x-min_x+grid, 1}, pivot=.center_center)
		draw_rect(line, col=Vec4{1, 1, 1, 0.08}, z_layer=.shadow)
		y += grid
	}
}

draw_entity_hitbox_debug :: proc(e: Entity) {
	hitbox, ok := get_entity_hitbox_rect(e)
	if !ok {
		return
	}

	layer: ZLayer = .top
	if is_game_paused() {
		layer = .pause_menu
	}
	draw_rect(hitbox, col=Vec4{0, 0, 0, 0}, outline_col=Vec4{1, 0.2, 0.2, 0.95}, z_layer=layer)
}

draw_entity_overlap_debug :: proc(e: Entity) {
	overlap_rect, ok := get_entity_overlap_rect(e)
	if !ok {
		return
	}

	draw_rect(overlap_rect, col=Vec4{0, 0, 0, 0}, outline_col=Vec4{0.2, 0.9, 1.0, 0.95}, z_layer=.top)
}

draw_entity_durability_debug :: proc(e: Entity) {
	if e.durability <= 0 {
		return
	}
	if e.kind == .player || e.kind == .item_pickup || e.kind == .dagger_projectile || e.kind == .movement_indicator_fx {
		return
	}

	pos := e.pos + Vec2{0, 14}
	sprite_rect, ok := get_entity_sprite_rect(e)
	if ok {
		pos = Vec2{(sprite_rect.x + sprite_rect.z) * 0.5, sprite_rect.w + 4}
	}

	label := fmt.tprintf("%v", e.durability)
	draw_text(pos, label, pivot=.bottom_center, z_layer=.top, col=Vec4{1, 0.95, 0.35, 0.95}, drop_shadow_col=Vec4{0, 0, 0, 0.8})
}

draw_entity_growth_debug :: proc(e: Entity) {
	if e.kind != .sapling_ent && e.kind != .sprout_ent {
		return
	}
	if e.growth_ready_time <= 0 {
		return
	}

	remaining := max(0.0, e.growth_ready_time-now())
	remaining_sec := int(math.ceil(remaining))
	next_stage := "Sapling" if e.kind == .sprout_ent else "Tree"
	label := fmt.tprintf("%v: %vs", next_stage, remaining_sec)

	pos := e.pos + Vec2{0, 16}
	sprite_rect, ok := get_entity_sprite_rect(e)
	if ok {
		pos = Vec2{(sprite_rect.x + sprite_rect.z) * 0.5, sprite_rect.w + 10}
	}

	layer: ZLayer = .top
	if is_game_paused() {
		layer = .pause_menu
	}
	draw_text(pos, label, pivot=.bottom_center, z_layer=layer, col=Vec4{0.72, 1.0, 0.72, 0.95}, drop_shadow_col=Vec4{0, 0, 0, 0.85}, scale=0.45)
}

draw_player_hit_cooldown_bar :: proc() {
	player := get_player()
	if !is_valid(player^) {
		return
	}
	if ctx.gs.hit_cooldown_duration <= 0 {
		return
	}

	remaining := max(0.0, ctx.gs.hit_cooldown_end_time-now())
	if remaining <= 0 {
		return
	}

	pct := math.clamp(f32(remaining/ctx.gs.hit_cooldown_duration), 0, 1)
	bar_size := Vec2{20, 3}
	bar_pos := player.pos + Vec2{0, -4}
	bg := shape.rect_make(bar_pos, bar_size, pivot=.top_center)
	fill_size := Vec2{bar_size.x * pct, bar_size.y}
	fill := shape.rect_make(Vec2{bg.x, bg.y}, fill_size, pivot=.bottom_left)

	draw_rect(bg, col=Vec4{0.05, 0.05, 0.05, 0.7}, outline_col=Vec4{1, 1, 1, 0.35}, z_layer=.top)
	draw_rect(fill, col=Vec4{1.0, 0.85, 0.2, 0.9}, z_layer=.top)
}

draw_terrain_water_tile_sprite :: proc(sprite: Sprite_Name, tile_center: Vec2, tile_size: Vec2, flip_x: bool) {
	if !sprite_is_loaded(sprite) {
		return
	}
	if !flip_x {
		draw_sprite_in_rect(sprite, tile_center-tile_size*0.5, tile_size, z_layer=.nil, pad_pct=0.0)
		return
	}

	src_size := get_sprite_size(sprite)
	if src_size.x <= 0 || src_size.y <= 0 {
		return
	}
	scale := Vec2{tile_size.x / src_size.x, tile_size.y / src_size.y}
	xform := utils.xform_scale(Vec2{-scale.x, scale.y})
	draw_sprite(tile_center, sprite, pivot=.center_center, xform=xform, z_layer=.nil)
}

get_entity_sort_y :: proc(e: Entity) -> f32 {
	hitbox, ok := get_entity_hitbox_rect(e)
	if ok {
		// Bottom edge of hitbox is the "feet" depth key.
		return hitbox.y
	}
	return e.pos.y
}

is_player_behind_entity :: proc(e: Entity) -> bool {
	if !e.blocks_player {
		return false
	}

	player := get_player()
	if !is_valid(player^) {
		return false
	}

	player_overlap_rect, ok_player := get_entity_overlap_rect(player^)
	if !ok_player {
		player_overlap_rect, ok_player = get_entity_hitbox_rect(player^)
	}
	if !ok_player {
		return false
	}

	entity_overlap_rect, ok_entity := get_entity_overlap_rect(e)
	if !ok_entity {
		return false
	}

	// Trigger when any part of the player overlap touches the entity overlap box, including edge-touch.
	if !rects_overlap_or_touch(player_overlap_rect, entity_overlap_rect) {
		return false
	}

	player_base_y := get_entity_sort_y(player^)
	entity_base_y := get_entity_sort_y(e)
	is_behind_entity := player_base_y > entity_base_y
	return is_behind_entity
}

rects_overlap_or_touch :: proc(a: shape.Rect, b: shape.Rect) -> bool {
	if a.z < b.x || b.z < a.x {
		return false
	}
	if a.w < b.y || b.w < a.y {
		return false
	}
	return true
}

get_entity_overlap_rect :: proc(e: Entity) -> (rect: shape.Rect, ok: bool) #optional_ok {
	if e.sprite == .nil {
		return {}, false
	}


	data := sprite_data[e.sprite]
	if data.overlap_box_size.x != 0 || data.overlap_box_size.y != 0 {
		return shape.rect_make(e.pos + data.overlap_box_offset, data.overlap_box_size, pivot=data.overlap_box_pivot), true
	}

	return get_entity_sprite_rect(e)
}

get_entity_sprite_rect :: proc(e: Entity) -> (rect: shape.Rect, ok: bool) #optional_ok {
	if e.sprite == .nil {
		return {}, false
	}

	size := get_sprite_size(e.sprite)
	size.x /= f32(get_frame_count(e.sprite))

	min := e.pos - size * utils.scale_from_pivot(e.draw_pivot) - e.draw_offset
	max := min + size
	return shape.Rect{min.x, min.y, max.x, max.y}, true
}

get_entity_hitbox_rect :: proc(e: Entity) -> (rect: shape.Rect, ok: bool) #optional_ok {
	#partial switch e.kind {
	case .player:
		// Keep player collision on the feet/body and not full sprite bounds.
		return shape.rect_make(e.pos, Vec2{8, 8}, pivot=.bottom_center), true
	case .oblisk_ent:
		// Obelisk collider is a narrow vertical blocker in the center.
		size := get_sprite_size(e.sprite)
		center := e.pos + Vec2{0, 0}

		return shape.rect_make(center, Vec2{size.x-2,size.y/2}, pivot=.bottom_center), true
	case .tree_ent:
		// Tree collider is only the trunk section so players can overlap canopy.
		size := get_sprite_size(e.sprite)
		center := e.pos + Vec2{0, 0}
		return shape.rect_make(center, Vec2{50, 30}, pivot=.bottom_center), true
	case .sapling_ent:
		return shape.rect_make(e.pos , Vec2{18, 13}, pivot=.bottom_center), true
	case .sprout_ent:
		return shape.rect_make(e.pos , Vec2{15, 10}, pivot=.bottom_center), true
	case .dagger_projectile:
		return shape.rect_make(e.pos, Vec2{4, 4}, pivot=.center_center), true
	case .nil:
		return {}, false
	case:
		// Fallback for unconfigured kinds: sprite bounds.
		if e.sprite == .nil {
			return {}, false
		}

		size := get_sprite_size(e.sprite)
		size.x /= f32(get_frame_count(e.sprite))

		min := e.pos - size * utils.scale_from_pivot(e.draw_pivot) - e.draw_offset
		max := min + size
		return shape.Rect{min.x, min.y, max.x, max.y}, true
	}
}

snap_to_grid :: proc(v: f32, grid: f32) -> f32 {
	if grid <= 0 do return v
	return math.round(v / grid) * grid
}

snap_vec2_to_grid :: proc(v: Vec2, grid: f32) -> Vec2 {
	return Vec2{snap_to_grid(v.x, grid), snap_to_grid(v.y, grid)}
}

snap_to_grid_floor :: proc(v: f32, grid: f32) -> f32 {
	if grid <= 0 do return v
	return math.floor(v / grid) * grid
}

snap_vec2_to_grid_center :: proc(v: Vec2, grid: f32) -> Vec2 {
	if grid <= 0 do return v
	half := grid * 0.5
	return Vec2{
		snap_to_grid_floor(v.x, grid) + half,
		snap_to_grid_floor(v.y, grid) + half,
	}
}

rounded_hitbox_sub_rects :: proc(rect: shape.Rect, corner_cut: f32) -> ([2]shape.Rect, bool) {
	size := shape.rect_size(rect)
	cut := corner_cut
	cut = min(cut, max(0.0, size.x*0.5-0.001))
	cut = min(cut, max(0.0, size.y*0.5-0.001))

	if cut <= 0 {
		return [2]shape.Rect{rect, rect}, false
	}

	// Union of these two rectangles creates corner-chamfered blocking.
	vertical := shape.Rect{rect.x + cut, rect.y, rect.z - cut, rect.w}
	horizontal := shape.Rect{rect.x, rect.y + cut, rect.z, rect.w - cut}
	return [2]shape.Rect{vertical, horizontal}, true
}

rounded_hitbox_collide_rect :: proc(a: shape.Rect, blocker: shape.Rect, corner_cut: f32) -> (hit: bool, push: Vec2) {
	subs, has_rounding := rounded_hitbox_sub_rects(blocker, corner_cut)
	if !has_rounding {
		return shape.collide(a, blocker)
	}

	best_push := Vec2{}
	best_len_sq: f32 = 0

	for sub in subs {
		h, p := shape.collide(a, sub)
		if !h do continue

		l2 := p.x*p.x + p.y*p.y
		if !hit || l2 < best_len_sq {
			hit = true
			best_push = p
			best_len_sq = l2
		}
	}

	return hit, best_push
}

rounded_hitbox_contains_point :: proc(rect: shape.Rect, p: Vec2, corner_cut: f32) -> bool {
	subs, has_rounding := rounded_hitbox_sub_rects(rect, corner_cut)
	if !has_rounding {
		return shape.rect_contains(rect, p)
	}

	for sub in subs {
		if shape.rect_contains(sub, p) {
			return true
		}
	}
	return false
}

should_grid_snap_entity :: proc(e: Entity) -> bool {
	#partial switch e.kind {
	case .player, .item_pickup, .dagger_projectile, .movement_indicator_fx, .grass_ent:
		return false
	case:
		return true
	}
}

apply_entity_grid_snap :: proc() {
	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !should_grid_snap_entity(e^) do continue
		e.pos = snap_vec2_to_grid_center(e.pos, ENTITY_GRID_SIZE)
	}
}

resolve_player_vs_hitboxes :: proc() {
	player := get_player()
	if !is_valid(player^) {
		return
	}
	prev_pos := player.pos

	player_hitbox, ok := get_entity_hitbox_rect(player^)
	if !ok {
		return
	}

	for _ in 0..<4 {
		collided_any := false

		for handle in get_all_ents() {
			e := entity_from_handle(handle)
			if !e.blocks_player do continue
			if e.handle.id == player.handle.id do continue

			blocker_hitbox, ok := get_entity_hitbox_rect(e^)
			if !ok do continue

			hit, push := rounded_hitbox_collide_rect(player_hitbox, blocker_hitbox, HITBOX_CORNER_CUT)
			if !hit do continue

			player.pos += push
			player_hitbox = shape.rect_shift(player_hitbox, push)
			collided_any = true
		}

		if collided_any {
			player.has_move_target = false
			player.has_queued_move_target = false
			player.queued_move_target = {}
		}

		if !collided_any do break
	}

	// Terrain collision fallback: water uses texture alpha, blocks use per-block hitbox config.
	player_hitbox, ok = get_entity_hitbox_rect(player^)
	if ok && (is_rect_touching_locked_world_area(player_hitbox) || is_rect_touching_water_collision(player_hitbox) || is_rect_touching_terrain_block_collision(player_hitbox)) {
		player.pos = prev_pos
		player.has_move_target = false
		player.has_queued_move_target = false
	}

	try_interact_pending_target(player)
}

item_name :: proc(item: Item_Kind) -> string {
	switch item {
	case .nil: return ""
	case .wood: return "Wood"
	case .stone: return "Stone"
	case .fiber: return "Fiber"
	case .stick: return "Stick"
	case .rope: return "Rope"
	case .sapling: return "Sapling"
	case .stone_blade: return "Stone Blade"
	case .stone_multitool: return "Stone Multitool"
	case .oblisk_fragment: return "Fragment"
	case .oblisk_core: return "Core"
	case .dagger_item: return "Dagger"
	case: return ""
	}
}

item_icon_sprite :: proc(item: Item_Kind) -> Sprite_Name {
	switch item {
	case .nil: return .nil
	case .wood: return .wood
	case .stone: return .stone
	case .fiber: return .fibre
	case .stick: return .sticks
	case .rope: return .rope
	case .sapling: return .sapling
	case .stone_blade: return .stone_blade
	case .stone_multitool: return .stone_multitool
	case .oblisk_fragment: return .oblisk_broken
	case .oblisk_core: return .oblisk
	case .dagger_item: return .dagger_item
	case: return .nil
	}
}

item_max_stack :: proc(item: Item_Kind) -> int {
	switch item {
	case .nil: return 0
	case .wood: return 99
	case .stone: return 99
	case .fiber: return 99
	case .stick: return 99
	case .rope: return 99
	case .sapling: return 99
	case .stone_blade: return 99
	case .stone_multitool: return 1
	case .oblisk_fragment: return 99
	case .oblisk_core: return 10
	case .dagger_item: return 1
	case: return 0
	}
}

item_hit_cooldown :: proc(item: Item_Kind) -> f64 {
	switch item {
	case .nil: return 0.6
	case .wood: return 0.6
	case .stone: return 0.7
	case .fiber: return 0.5
	case .stick: return 0.45
	case .rope: return 0.5
	case .sapling: return 0.55
	case .stone_blade: return 0.35
	case .stone_multitool: return 0.4
	case .oblisk_fragment: return 0.5
	case .oblisk_core: return 0.6
	case .dagger_item: return 0.45
	case: return 0.6
	}
}

item_hit_durability_multiplier :: proc(item: Item_Kind) -> f32 {
	#partial switch item {
	case .wood: return 0
	case .fiber: return 0
	case .rope: return 0
	case .stone_blade: return 0.5
	case .stone_multitool: return 2.0
	case: return 1.0
	}
}

item_swing_sprite :: proc(item: Item_Kind) -> Sprite_Name {
	#partial switch item {
	case .stone_multitool:
		return .stone_multitool_swing
	case:
		return item_icon_sprite(item)
	}
}

start_hit_cooldown_for_item :: proc(item: Item_Kind) {
	dur := item_hit_cooldown(item)
	ctx.gs.hit_cooldown_duration = dur
	ctx.gs.hit_cooldown_end_time = now() + dur
}

is_hit_cooldown_ready :: proc() -> bool {
	return now() >= ctx.gs.hit_cooldown_end_time
}

get_hit_item_multiplier :: proc(hitter: ^Entity) -> f32 {
	mult: f32 = 1.0
	if is_valid(hitter^) && hitter.kind == .player {
		item, count := get_equipped_item()
		if count <= 0 {
			item = .nil
		}
		mult = item_hit_durability_multiplier(item)
	}
	return mult
}

get_hit_durability_damage :: proc(hitter: ^Entity) -> int {
	mult := get_hit_item_multiplier(hitter)
	return max(0, int(math.ceil(mult)))
}

start_player_swing_fx :: proc(target_x: f32 = 0, use_target_side:=false) {
	player := get_player()
	if !is_valid(player^) {
		return
	}

	item, count := get_equipped_item()
	if count <= 0 {
		return
	}

	sprite := item_swing_sprite(item)
	if sprite == .nil {
		return
	}

	dir_x: f32 = 1
	if use_target_side {
		if target_x < player.pos.x {
			dir_x = -1
		}
	} else if player.last_known_x_dir < 0 {
		dir_x = -1
	}
	dir := Vec2{dir_x, 0}

	ctx.gs.swing_active = true
	ctx.gs.swing_sprite = sprite
	ctx.gs.swing_anim_index = 0
	ctx.gs.swing_next_frame_end_time = 0
	ctx.gs.swing_dir = dir
	ctx.gs.swing_rotation = 0
	if dir.x < 0 {
		ctx.gs.swing_rotation = 180
	}
}

update_player_swing_fx :: proc() {
	if !ctx.gs.swing_active || ctx.gs.swing_sprite == .nil {
		return
	}

	frame_count := get_frame_count(ctx.gs.swing_sprite)
	if frame_count <= 0 {
		ctx.gs.swing_active = false
		return
	}

	if ctx.gs.swing_next_frame_end_time == 0 {
		ctx.gs.swing_next_frame_end_time = now() + 0.05
	}

	if end_time_up(ctx.gs.swing_next_frame_end_time) {
		ctx.gs.swing_anim_index += 1
		ctx.gs.swing_next_frame_end_time = 0
		if ctx.gs.swing_anim_index >= frame_count {
			ctx.gs.swing_anim_index = frame_count - 1
			ctx.gs.swing_active = false
		}
	}
}

inventory_add_item :: proc(inv: ^Inventory_State, item: Item_Kind, count: int) -> (added: int) {
	if item == .nil || count <= 0 {
		return 0
	}

	remaining := count
	max_stack := item_max_stack(item)

	// Fill existing stacks first, prioritizing hotbar slots.
	for i in HOTBAR_SLOT_START..<INVENTORY_SLOT_COUNT {
		slot := &inv.slots[i]
		if slot.item != item do continue
		if slot.count >= max_stack do continue

		free := max_stack - slot.count
		to_add := min(free, remaining)
		slot.count += to_add
		remaining -= to_add
		if remaining <= 0 do return count
	}
	for i in 0..<HOTBAR_SLOT_START {
		slot := &inv.slots[i]
		if slot.item != item do continue
		if slot.count >= max_stack do continue

		free := max_stack - slot.count
		to_add := min(free, remaining)
		slot.count += to_add
		remaining -= to_add
		if remaining <= 0 do return count
	}

	// Then use empty slots, prioritizing hotbar slots.
	for i in HOTBAR_SLOT_START..<INVENTORY_SLOT_COUNT {
		slot := &inv.slots[i]
		if slot.item != .nil do continue

		to_add := min(max_stack, remaining)
		slot.item = item
		slot.count = to_add
		remaining -= to_add
		if remaining <= 0 do return count
	}
	for i in 0..<HOTBAR_SLOT_START {
		slot := &inv.slots[i]
		if slot.item != .nil do continue

		to_add := min(max_stack, remaining)
		slot.item = item
		slot.count = to_add
		remaining -= to_add
		if remaining <= 0 do return count
	}

	return count - remaining
}

get_total_count_in_slots :: proc(slots: []Inventory_Slot, item: Item_Kind) -> int {
	total := 0
	for slot in slots {
		if slot.item == item {
			total += slot.count
		}
	}
	return total
}

get_total_non_empty_count_in_slots :: proc(slots: []Inventory_Slot) -> int {
	total := 0
	for slot in slots {
		if slot.item != .nil && slot.count > 0 {
			total += slot.count
		}
	}
	return total
}

is_ui_overlay_open :: proc(mask: u32) -> bool {
	return (ctx.gs.ui_overlay_mask & mask) != 0
}

is_any_ui_overlay_open :: proc() -> bool {
	return ctx.gs.ui_overlay_mask != 0
}

set_ui_overlay_open :: proc(mask: u32, open: bool) {
	if open {
		ctx.gs.ui_overlay_mask |= mask
	} else {
		ctx.gs.ui_overlay_mask &= ~mask
	}
}

close_all_ui_overlays :: proc() {
	return_inventory_overlay_items_to_inventory(&ctx.gs.inventory)
	ctx.gs.ui_overlay_mask = 0
	ctx.gs.inventory.open = false
}

is_game_paused :: proc() -> bool {
	return is_ui_overlay_open(UI_OVERLAY_PAUSE)
}

crafting_set_output :: proc(inv: ^Inventory_State, item: Item_Kind, count: int) {
	if item == .nil || count <= 0 {
		inv.crafting_output = {}
		return
	}
	inv.crafting_output = {item=item, count=count}
}

update_crafting_output :: proc(inv: ^Inventory_State) {
	input := inv.crafting_slots[:]
	if get_total_non_empty_count_in_slots(input) == 0 {
		inv.crafting_recipe_index = -1
		crafting_set_output(inv, .nil, 0)
		return
	}

	for i in 0..<len(crafting_recipes) {
		r := crafting_recipes[i]
		matches := true

		for slot_i in 0..<CRAFT_INPUT_SLOT_COUNT {
			req := r.pattern[slot_i]
			slot := input[slot_i]
			if req.item == .nil || req.count <= 0 {
				if slot.item != .nil && slot.count > 0 {
					matches = false
					break
				}
			} else {
				if slot.item != req.item || slot.count < req.count {
					matches = false
					break
				}
			}
		}

		if !matches do continue

		inv.crafting_recipe_index = i
		crafting_set_output(inv, r.output.item, r.output.count)
		return
	}

	inv.crafting_recipe_index = -1
	crafting_set_output(inv, .nil, 0)
}

consume_recipe_pattern_slots :: proc(inv: ^Inventory_State, pattern: [CRAFT_INPUT_SLOT_COUNT]Inventory_Slot) -> bool {
	for i in 0..<CRAFT_INPUT_SLOT_COUNT {
		req := pattern[i]
		if req.item == .nil || req.count <= 0 do continue

		slot := inv.crafting_slots[i]
		if slot.item != req.item || slot.count < req.count {
			return false
		}
	}

	for i in 0..<CRAFT_INPUT_SLOT_COUNT {
		req := pattern[i]
		if req.item == .nil || req.count <= 0 do continue

		slot := &inv.crafting_slots[i]
		slot.count -= req.count
		if slot.count <= 0 {
			slot^ = {}
		}
	}

	return true
}

try_consume_crafting_ingredients_for_output :: proc(inv: ^Inventory_State, output: Inventory_Slot) -> bool {
	if output.item == .nil || output.count <= 0 {
		return false
	}
	if inv.crafting_recipe_index < 0 || inv.crafting_recipe_index >= len(crafting_recipes) {
		return false
	}

	r := crafting_recipes[inv.crafting_recipe_index]
	if r.output.item != output.item || r.output.count != output.count {
		return false
	}

	return consume_recipe_pattern_slots(inv, r.pattern)
}

return_slot_to_inventory_or_drop :: proc(inv: ^Inventory_State, slot: ^Inventory_Slot) {
	if slot.item == .nil || slot.count <= 0 {
		slot^ = {}
		return
	}

	remaining := slot.count
	added := inventory_add_item(inv, slot.item, remaining)
	remaining -= added
	item := slot.item
	slot^ = {}

	if remaining <= 0 {
		return
	}

	drop_pos := Vec2{}
	player := get_player()
	if is_valid(player^) {
		drop_pos = get_inventory_drop_world_pos(player.pos + Vec2{1, 0})
	} else {
		drop_pos = {}
	}
	spawn_item_pickup(item, remaining, drop_pos)
}

return_inventory_overlay_items_to_inventory :: proc(inv: ^Inventory_State) {
	if inv.dragging && inv.drag_slot.item != .nil && inv.drag_slot.count > 0 {
		return_slot_to_inventory_or_drop(inv, &inv.drag_slot)
		clear_inventory_drag(inv)
	}

	for i in 0..<CRAFT_INPUT_SLOT_COUNT {
		return_slot_to_inventory_or_drop(inv, &inv.crafting_slots[i])
	}

	inv.crafting_recipe_index = -1
	crafting_set_output(inv, .nil, 0)
}

inventory_update :: proc() {
	inv := &ctx.gs.inventory

	if key_pressed(.TAB) {
		consume_key_pressed(.TAB)
		next_open := !is_ui_overlay_open(UI_OVERLAY_INVENTORY)
		if !next_open && inv.open {
			return_inventory_overlay_items_to_inventory(inv)
		}
		inv.open = next_open
		set_ui_overlay_open(UI_OVERLAY_INVENTORY, next_open)
	}

	if !inv.open && inv.dragging && inv.drag_slot.item != .nil && inv.drag_slot.count > 0 {
		return_inventory_overlay_items_to_inventory(inv)
	}

	update_crafting_output(inv)

	// Hotbar quick equip (1..6).
	for i in 0..<HOTBAR_SLOT_COUNT {
		key := Key_Code(int(Key_Code._1) + i)
		if key_pressed(key) {
			consume_key_pressed(key)
			inv.equipped_slot = HOTBAR_SLOT_START + i
		}
	}

	// Mouse wheel cycles equipped hotbar slot.
	if state.scroll_y != 0 {
		dir := 1
		if state.scroll_y > 0 {
			dir = -1
		}
		current := inv.equipped_slot
		if current < HOTBAR_SLOT_START || current >= HOTBAR_SLOT_START+HOTBAR_SLOT_COUNT {
			current = HOTBAR_SLOT_START
		}

		next_local := (current - HOTBAR_SLOT_START) + dir
		for next_local < 0 do next_local += HOTBAR_SLOT_COUNT
		next_local = next_local % HOTBAR_SLOT_COUNT
		inv.equipped_slot = HOTBAR_SLOT_START + next_local
	}

	player := get_player()
	if !is_valid(player^) {
		return
	}

	// Auto-pickup nearby items.
	pickup_range_sq := AUTO_PICKUP_RADIUS * AUTO_PICKUP_RADIUS
	picked_any := false
	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if e.kind != .item_pickup do continue
		if now() < e.pickup_ready_time do continue

		diff := e.pos - player.pos
		d2 := diff.x*diff.x + diff.y*diff.y
		if d2 > pickup_range_sq do continue

		added := inventory_add_item(inv, e.pickup_item, e.pickup_count)
		if added > 0 {
			e.pickup_count -= added
			picked_any = true
			if e.pickup_count <= 0 {
				entity_destroy(e)
			}
		}
	}

	if picked_any {
		sound_play("event:/schloop", pos=player.pos)
	}
}

draw_inventory_slot :: proc(rect: shape.Rect, slot: Inventory_Slot, selected: bool, hover: bool, hotbar:=false) {
	fill := Vec4{0.05, 0.05, 0.05, 0.72}
	if hover {
		fill = Vec4{0.1, 0.1, 0.1, 0.82}
	}

	outline := Vec4{1, 1, 1, 0.25}
	if hotbar {
		outline = Vec4{0.65, 0.9, 1.0, 0.45}
	}
	if selected {
		outline = Vec4{1, 0.9, 0.2, 0.95}
	}

	draw_rect(rect, col=fill, outline_col=outline, z_layer=.ui)

	if slot.item == .nil || slot.count <= 0 {
		return
	}

	icon := item_icon_sprite(slot.item)
	if icon != .nil {
		draw_sprite_in_rect(icon, rect.xy, shape.rect_size(rect), col=Vec4{1, 1, 1, 0.9}, z_layer=.ui, pad_pct=0.2)
	}

	if slot.count > 1 {
		count_text := fmt.tprintf("%v", slot.count)
		draw_text(rect.zw + Vec2{-2, -1}, count_text, pivot=.top_right, z_layer=.ui, col=Vec4{1, 1, 1, 0.95}, drop_shadow_col=Vec4{0, 0, 0, 0.6})
	}
}

get_inventory_drop_world_pos :: proc(mouse_world_pos: Vec2) -> Vec2 {
	player := get_player()
	if !is_valid(player^) {
		return mouse_world_pos
	}

	dir := mouse_world_pos - player.pos
	len_sq := dir.x*dir.x + dir.y*dir.y
	if len_sq <= 0.0001 {
		dir = Vec2{player.flip_x ? -1 : 1, 0}
	} else {
		dir /= math.sqrt(len_sq)
	}

	return player.pos + dir * DROP_OUTSIDE_PICKUP_RADIUS
}

hotbar_slot_rect :: proc(i: int) -> shape.Rect {
	cx, by := screen_pivot(.bottom_center)
	slot_size := Vec2{22, 22}
	gap: f32 = 3
	total_w := f32(HOTBAR_SLOT_COUNT)*slot_size.x + f32(HOTBAR_SLOT_COUNT-1)*gap
	start := Vec2{cx - total_w*0.5, by + 4}
	pos := start + Vec2{f32(i) * (slot_size.x + gap), 0}
	return shape.rect_make(pos, slot_size, pivot=.bottom_left)
}

inventory_panel_rect :: proc() -> shape.Rect {
	cx, cy := screen_pivot(.center_center)
	panel_size := Vec2{170, 92}
	return shape.rect_make(Vec2{cx - 50, cy - 10}, panel_size, pivot=.center_center)
}

crafting_panel_rect :: proc() -> shape.Rect {
	inv := inventory_panel_rect()
	panel_size := Vec2{220, 92}
	inv_h := inv.w - inv.y
	cx := (inv.x + inv.z) * 0.5
	cy := (inv.y + inv.w) * 0.5 + inv_h*0.5 + panel_size.y*0.5 + 8
	return shape.rect_make(Vec2{cx, cy}, panel_size, pivot=.center_center)
}

inventory_grid_slot_rect :: proc(i: int) -> shape.Rect {
	panel := inventory_panel_rect()

	cols :: 6
	slot_size := Vec2{22, 22}
	gap: f32 = 3
	grid_start := Vec2{panel.x + 8, panel.y + 8}

	col := i % cols
	row := i / cols
	pos := grid_start + Vec2{f32(col) * (slot_size.x + gap), f32(1-row) * (slot_size.y + gap)}
	return shape.rect_make(pos, slot_size, pivot=.bottom_left)
}

crafting_input_slot_rect :: proc(i: int) -> shape.Rect {
	panel := crafting_panel_rect()

	slot_size := Vec2{22, 22}
	gap: f32 = 3
	grid_start := Vec2{panel.x + 58, panel.y + 8}

	col := i % CRAFT_INPUT_COLS
	row := i / CRAFT_INPUT_COLS
	pos := grid_start + Vec2{f32(col) * (slot_size.x + gap), f32(CRAFT_INPUT_ROWS-1-row) * (slot_size.y + gap)}
	return shape.rect_make(pos, slot_size, pivot=.bottom_left)
}

crafting_output_slot_rect :: proc() -> shape.Rect {
	panel := crafting_panel_rect()
	slot_size := Vec2{22, 22}
	return shape.rect_make(Vec2{panel.x + 154, panel.y + 35}, slot_size, pivot=.bottom_left)
}

find_inventory_slot_at_mouse :: proc(inv: ^Inventory_State, mouse_pos: Vec2) -> (slot_index: int, ok: bool) {
	// Prefer panel slots while open since they are drawn on top of hotbar.
	if inv.open {
		for i in 0..<INVENTORY_SLOT_COUNT {
			rect := inventory_grid_slot_rect(i)
			if shape.rect_contains(rect, mouse_pos) {
				return i, true
			}
		}
	}

	for i in 0..<HOTBAR_SLOT_COUNT {
		rect := hotbar_slot_rect(i)
		if shape.rect_contains(rect, mouse_pos) {
			return HOTBAR_SLOT_START + i, true
		}
	}

	return 0, false
}

find_crafting_input_slot_at_mouse :: proc(inv: ^Inventory_State, mouse_pos: Vec2) -> (slot_index: int, ok: bool) {
	if !inv.open {
		return 0, false
	}
	for i in 0..<CRAFT_INPUT_SLOT_COUNT {
		rect := crafting_input_slot_rect(i)
		if shape.rect_contains(rect, mouse_pos) {
			return i, true
		}
	}
	return 0, false
}

is_crafting_output_hovered :: proc(inv: ^Inventory_State, mouse_pos: Vec2) -> bool {
	if !inv.open {
		return false
	}
	return shape.rect_contains(crafting_output_slot_rect(), mouse_pos)
}

clear_inventory_drag :: proc(inv: ^Inventory_State) {
	inv.dragging = false
	inv.drag_from_slot = -1
	inv.drag_from_kind = .none
	inv.drag_slot = {}
	inv.right_drag_last_slot = -1
	inv.right_drag_last_kind = .none
}

pick_up_slot_into_hand :: proc(inv: ^Inventory_State, slot: ^Inventory_Slot, from_kind: Drag_From_Kind, from_slot: int) -> bool {
	if slot.item == .nil || slot.count <= 0 {
		return false
	}
	if inv.dragging {
		return false
	}
	inv.dragging = true
	inv.drag_from_slot = from_slot
	inv.drag_from_kind = from_kind
	inv.drag_slot = slot^
	slot^ = {}
	return true
}

place_held_stack_swap :: proc(inv: ^Inventory_State, dst: ^Inventory_Slot) -> bool {
	if !inv.dragging || inv.drag_slot.item == .nil || inv.drag_slot.count <= 0 {
		return false
	}

	if dst.item == inv.drag_slot.item {
		max_stack := item_max_stack(dst.item)
		if max_stack > 0 {
			free := max(0, max_stack-dst.count)
			to_add := min(free, inv.drag_slot.count)
			dst.count += to_add
			inv.drag_slot.count -= to_add
			if inv.drag_slot.count <= 0 {
				clear_inventory_drag(inv)
			}
			return to_add > 0
		}
	}

	tmp := dst^
	dst^ = inv.drag_slot
	inv.drag_slot = tmp
	if inv.drag_slot.item == .nil || inv.drag_slot.count <= 0 {
		clear_inventory_drag(inv)
	}
	return true
}

place_held_one :: proc(inv: ^Inventory_State, dst: ^Inventory_Slot) -> bool {
	if !inv.dragging || inv.drag_slot.item == .nil || inv.drag_slot.count <= 0 {
		return false
	}

	if dst.item == .nil || dst.count <= 0 {
		dst.item = inv.drag_slot.item
		dst.count = 1
		inv.drag_slot.count -= 1
	} else {
		if dst.item != inv.drag_slot.item {
			return false
		}
		if dst.count >= item_max_stack(dst.item) {
			return false
		}
		dst.count += 1
		inv.drag_slot.count -= 1
	}

	if inv.drag_slot.count <= 0 {
		clear_inventory_drag(inv)
	}
	return true
}

draw_inventory_ui :: proc() {
	inv := &ctx.gs.inventory
	mouse_pos := mouse_pos_in_current_space()
	update_crafting_output(inv)

	if key_pressed(.LEFT_MOUSE) {
		consumed_click := false

		// Claim crafting output first.
		if is_crafting_output_hovered(inv, mouse_pos) && inv.crafting_output.item != .nil && inv.crafting_output.count > 0 {
			if inv.dragging && inv.drag_slot.item == inv.crafting_output.item {
				max_stack := item_max_stack(inv.drag_slot.item)
				free := max(0, max_stack-inv.drag_slot.count)
				if free >= inv.crafting_output.count && try_consume_crafting_ingredients_for_output(inv, inv.crafting_output) {
					inv.drag_slot.count += inv.crafting_output.count
					update_crafting_output(inv)
				}
			} else if !inv.dragging && try_consume_crafting_ingredients_for_output(inv, inv.crafting_output) {
				inv.dragging = true
				inv.drag_from_slot = -1
				inv.drag_from_kind = .craft_output
				inv.drag_slot = inv.crafting_output
				update_crafting_output(inv)
			}
			consumed_click = true
		}

		// Then crafting input slots.
		if !consumed_click {
			craft_i, craft_ok := find_crafting_input_slot_at_mouse(inv, mouse_pos)
			if craft_ok {
				slot := &inv.crafting_slots[craft_i]
				if inv.dragging {
					_ = place_held_stack_swap(inv, slot)
				} else {
					_ = pick_up_slot_into_hand(inv, slot, .craft_input, craft_i)
				}
				update_crafting_output(inv)
				consumed_click = true
			}
		}

		// Finally inventory/hotbar slots.
		if !consumed_click {
			slot_index, slot_ok := find_inventory_slot_at_mouse(inv, mouse_pos)
			if slot_ok {
				inv.equipped_slot = slot_index
				if inv.open {
					slot := &inv.slots[slot_index]
					if inv.dragging {
						_ = place_held_stack_swap(inv, slot)
					} else {
						_ = pick_up_slot_into_hand(inv, slot, .inventory, slot_index)
					}
				}
				consumed_click = true
			}
		}

		if consumed_click {
			consume_key_pressed(.LEFT_MOUSE)
		}
	}

	if key_down(.RIGHT_MOUSE) && inv.dragging {
		target_kind := Drag_From_Kind.none
		target_slot := -1
		target_is_crafting := false

		slot_index, slot_ok := find_inventory_slot_at_mouse(inv, mouse_pos)
		if slot_ok {
			target_kind = .inventory
			target_slot = slot_index
		} else {
			craft_i, craft_ok := find_crafting_input_slot_at_mouse(inv, mouse_pos)
			if craft_ok {
				target_kind = .craft_input
				target_slot = craft_i
				target_is_crafting = true
			}
		}

		is_new_target := target_kind != inv.right_drag_last_kind || target_slot != inv.right_drag_last_slot
		if target_kind != .none && (key_pressed(.RIGHT_MOUSE) || is_new_target) {
			if target_kind == .inventory {
				inv.equipped_slot = target_slot
				_ = place_held_one(inv, &inv.slots[target_slot])
			} else if target_is_crafting {
				_ = place_held_one(inv, &inv.crafting_slots[target_slot])
				update_crafting_output(inv)
			}
			inv.right_drag_last_kind = target_kind
			inv.right_drag_last_slot = target_slot
		} else if target_kind == .none {
			inv.right_drag_last_kind = .none
			inv.right_drag_last_slot = -1
		}
	}

	if key_released(.RIGHT_MOUSE) {
		inv.right_drag_last_kind = .none
		inv.right_drag_last_slot = -1
	}

	// Hotbar
	{
		for i in 0..<HOTBAR_SLOT_COUNT {
			rect := hotbar_slot_rect(i)
			hover := shape.rect_contains(rect, mouse_pos)
			slot_index := HOTBAR_SLOT_START + i
			draw_inventory_slot(rect, inv.slots[slot_index], selected=inv.equipped_slot == slot_index, hover=hover, hotbar=true)
		}

		cx, by := screen_pivot(.bottom_center)
		equipped := inv.slots[inv.equipped_slot]
		label := "Equipped: none"
		if equipped.item != .nil {
			label = fmt.tprintf("Equipped: %v", item_name(equipped.item))
		}
		draw_text(Vec2{cx, by + 29}, label, pivot=.bottom_center, z_layer=.ui, col=Vec4{1, 1, 1, 0.8}, drop_shadow_col=Vec4{}, scale=0.4)
	}

	if !inv.open {
		return
	}

	// Full inventory panel
	{
		inv_panel := inventory_panel_rect()
		draw_rect(inv_panel, col=Vec4{0.02, 0.02, 0.02, 0.9}, outline_col=Vec4{1, 1, 1, 0.25}, z_layer=.ui)
		draw_text(Vec2{inv_panel.x + 6, inv_panel.w - 4}, "Inventory [TAB]", pivot=.top_left, z_layer=.ui, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{})

		for i in 0..<INVENTORY_SLOT_COUNT {
			rect := inventory_grid_slot_rect(i)
			hover := shape.rect_contains(rect, mouse_pos)
			draw_inventory_slot(rect, inv.slots[i], selected=inv.equipped_slot == i, hover=hover)
		}

		craft_panel := crafting_panel_rect()
		draw_rect(craft_panel, col=Vec4{0.02, 0.02, 0.02, 0.9}, outline_col=Vec4{1, 1, 1, 0.25}, z_layer=.ui)
		draw_text(Vec2{craft_panel.x + 6, craft_panel.w - 4}, "Craft", pivot=.top_left, z_layer=.ui, col=Vec4{1, 1, 1, 0.8}, drop_shadow_col=Vec4{})

		for i in 0..<CRAFT_INPUT_SLOT_COUNT {
			rect := crafting_input_slot_rect(i)
			hover := shape.rect_contains(rect, mouse_pos)
			draw_inventory_slot(rect, inv.crafting_slots[i], selected=false, hover=hover)
		}

		out_rect := crafting_output_slot_rect()
		out_hover := shape.rect_contains(out_rect, mouse_pos)
		draw_inventory_slot(out_rect, inv.crafting_output, selected=false, hover=out_hover)
		draw_text(out_rect.xy + Vec2{-10, 10}, "=>", z_layer=.ui, col=Vec4{1, 1, 1, 0.75}, drop_shadow_col=Vec4{})
	}

	if inv.dragging && inv.drag_slot.item != .nil && inv.drag_slot.count > 0 {
		icon := item_icon_sprite(inv.drag_slot.item)
		size := Vec2{22, 22}
		rect := shape.rect_make(mouse_pos + Vec2{10, -10}, size, pivot=.center_center)
		if icon != .nil {
			draw_rect(rect, col=Vec4{0.05, 0.05, 0.05, 0.5}, outline_col=Vec4{1, 1, 1, 0.2}, z_layer=.tooltip)
			draw_sprite_in_rect(icon, rect.xy, shape.rect_size(rect), col=Vec4{1, 1, 1, 0.9}, z_layer=.tooltip, pad_pct=0.2)
		}
		if inv.drag_slot.count > 1 {
			count_text := fmt.tprintf("%v", inv.drag_slot.count)
			draw_text(rect.zw + Vec2{-2, -1}, count_text, pivot=.top_right, z_layer=.tooltip, col=Vec4{1, 1, 1, 0.95}, drop_shadow_col=Vec4{0, 0, 0, 0.6})
		}
	}
}

spawn_item_pickup :: proc(item: Item_Kind, count: int, pos: Vec2) -> ^Entity {
	e := entity_create(.item_pickup)
	e.pos = pos
	e.pickup_item = item
	e.pickup_count = max(1, count)
	e.pickup_ready_time = 0
	e.sprite = item_icon_sprite(item)
	return e
}

spawn_item_pickup_towards_player :: proc(item: Item_Kind, count: int, pos: Vec2) -> ^Entity {
	e := spawn_item_pickup(item, count, pos)

	player := get_player()
	if is_valid(player^) {
		to_player := player.pos - pos
		len_sq := to_player.x*to_player.x + to_player.y*to_player.y
		if len_sq > 0.0001 {
			to_player /= math.sqrt(len_sq)
			e.vel = to_player * ITEM_DROP_BOUNCE_SPEED
		}
	}

	e.pickup_ready_time = now() + ITEM_DROP_PICKUP_DELAY_SEC
	return e
}

compute_hit_drop_spawn_pos :: proc(target: ^Entity) -> Vec2 {
	base := target.pos + Vec2{0, 8}
	player := get_player()
	if !is_valid(player^) {
		return base
	}

	mid := (player.pos + target.pos) * 0.5
	hitbox, ok := get_entity_hitbox_rect(target^)
	if !ok {
		return mid
	}

	edge := Vec2{
		math.clamp(player.pos.x, hitbox.x, hitbox.z),
		math.clamp(player.pos.y, hitbox.y, hitbox.w),
	}

	offset := mid - edge
	dist := linalg.length(offset)
	if dist > HIT_DROP_MAX_FROM_EDGE && dist > 0.0001 {
		offset *= HIT_DROP_MAX_FROM_EDGE / dist
	}

	return edge + offset
}

should_roll_bonus_sapling_drop :: proc(kind: Entity_Kind) -> bool {
	#partial switch kind {
	case .tree_ent, .sapling_ent, .sprout_ent:
		return true
	case:
		return false
	}
}

get_place_approach_pos :: proc(player_pos: Vec2, place_pos: Vec2) -> Vec2 {
	to_player := player_pos - place_pos
	len_sq := to_player.x*to_player.x + to_player.y*to_player.y
	if len_sq <= 0.0001 {
		return place_pos + Vec2{INTERACT_RANGE - 2, 0}
	}

	to_player /= math.sqrt(len_sq)
	return place_pos + to_player * (INTERACT_RANGE - 2)
}

place_entity_from_item :: proc(item: Item_Kind, pos: Vec2) -> bool {
	#partial switch item {
	case .sapling:
		e := entity_create(.sapling_ent)
		e.pos = pos
		return true
	case:
		return false
	}
}

try_begin_place_equipped_item :: proc(mouse_world: Vec2) -> bool {
	item, count := get_equipped_item()
	if item != .sapling || count <= 0 {
		return false
	}

	_, hit_ok := find_hittable_entity_at_world_pos(mouse_world)
	if hit_ok {
		return false
	}

	place_pos := snap_vec2_to_grid_center(mouse_world, ENTITY_GRID_SIZE)
	if is_world_position_blocked_for_player(place_pos) {
		return false
	}

	player := get_player()
	if !is_valid(player^) {
		return false
	}

	diff := place_pos - player.pos
	d2 := diff.x*diff.x + diff.y*diff.y
	if d2 <= INTERACT_RANGE*INTERACT_RANGE {
		if !consume_equipped_item(1) {
			return false
		}
		return place_entity_from_item(item, place_pos)
	}

	player.pending_place_item = item
	player.pending_place_pos = place_pos
	player.has_pending_place = true

	approach := get_place_approach_pos(player.pos, place_pos)
	set_player_move_target_with_detour(player, approach)
	return true
}

try_place_pending_item :: proc(player: ^Entity) {
	if !player.has_pending_place {
		return
	}

	diff := player.pending_place_pos - player.pos
	d2 := diff.x*diff.x + diff.y*diff.y
	if d2 > INTERACT_RANGE*INTERACT_RANGE {
		return
	}
	if is_world_position_blocked_for_player(player.pending_place_pos) {
		player.has_pending_place = false
		player.pending_place_item = .nil
		return
	}
	_, hit_ok := find_hittable_entity_at_world_pos(player.pending_place_pos)
	if hit_ok {
		player.has_pending_place = false
		player.pending_place_item = .nil
		return
	}

	item := player.pending_place_item
	if !consume_equipped_item(1) {
		player.has_pending_place = false
		player.pending_place_item = .nil
		return
	}

	_ = place_entity_from_item(item, player.pending_place_pos)
	player.has_pending_place = false
	player.pending_place_item = .nil
}

spawn_movement_indicator :: proc(pos: Vec2) -> ^Entity {
	e := entity_create(.movement_indicator_fx)
	e.pos = pos
	return e
}

random01_from_seed :: proc(seed0: u64) -> f32 {
	seed := seed0
	seed = seed*6364136223846793005 + 1
	r := u32((seed >> 32) & 0xFFFF_FFFF)
	return f32(r) / 4294967295.0
}

roll_chance :: proc(chance: f32, salt: u64) -> bool {
	if chance <= 0 {
		return false
	}
	if chance >= 1 {
		return true
	}

	t := u64(now() * 1000000.0)
	seed := t + u64(ctx.gs.ticks)*1315423911 + salt*1099511628211
	return random01_from_seed(seed) < chance
}

entity_on_hit_noop :: proc(_: ^Entity, _: ^Entity) {}

schedule_entity_growth :: proc(e: ^Entity, base_sec: f64, jitter_sec: f64, salt: u64) {
	if base_sec <= 0 {
		e.growth_ready_time = 0
		return
	}

	j := max(0.0, jitter_sec)
	seed := u64(e.handle.id)*11400714819323198485 + salt*6364136223846793005
	offset := (f64(random01_from_seed(seed))*2.0 - 1.0) * j
	delay := max(1.0, base_sec+offset)
	e.growth_ready_time = now() + delay
}

growth_hitbox_for_kind_at_pos :: proc(kind: Entity_Kind, pos: Vec2) -> (shape.Rect, bool) {
	#partial switch kind {
	case .sapling_ent:
		return shape.rect_make(pos, Vec2{18, 13}, pivot=.bottom_center), true
	case .tree_ent:
		return shape.rect_make(pos, Vec2{50, 30}, pivot=.bottom_center), true
	case:
		return {}, false
	}
}

can_grow_entity_into_kind :: proc(e: ^Entity, next_kind: Entity_Kind) -> bool {
	next_hitbox, ok := growth_hitbox_for_kind_at_pos(next_kind, e.pos)
	if !ok {
		return true
	}

	player := get_player()
	if is_valid(player^) {
		player_hitbox, player_ok := get_entity_hitbox_rect(player^)
		if player_ok {
			hit, _ := rounded_hitbox_collide_rect(player_hitbox, next_hitbox, HITBOX_CORNER_CUT)
			if hit {
				return false
			}
		}
	}

	return true
}

grow_entity_into_kind :: proc(e: ^Entity, next_kind: Entity_Kind) {
	if !can_grow_entity_into_kind(e, next_kind) {
		e.growth_ready_time = now() + GROWTH_RETRY_DELAY_SEC
		return
	}

	next := entity_create(next_kind)
	next.pos = e.pos
	entity_destroy(e)
}

entity_on_hit_tree :: proc(target: ^Entity, hitter: ^Entity) {
	chance := TREE_WOOD_HIT_DROP_CHANCE * get_hit_item_multiplier(hitter)
	if roll_chance(chance, u64(target.handle.id)) {
		spawn_item_pickup_towards_player(.wood, 1, compute_hit_drop_spawn_pos(target))
	}
}

update_entity_durability_regen :: proc(e: ^Entity) {
	if e.durability_max <= 0 do return
	if e.durability <= 0 do return
	if e.durability >= e.durability_max {
		e.durability_regen_accum = 0
		return
	}

	elapsed_since_hit := now() - e.last_hit_time
	if elapsed_since_hit < DURABILITY_REGEN_DELAY_SEC {
		return
	}

	e.durability_regen_accum += ctx.delta_t * DURABILITY_REGEN_PER_SEC
	for e.durability_regen_accum >= 1.0 && e.durability < e.durability_max {
		e.durability += 1
		e.durability_regen_accum -= 1.0
	}
	if e.durability >= e.durability_max {
		e.durability = e.durability_max
		e.durability_regen_accum = 0
	}
}

update_entity_hit_flash :: proc(e: ^Entity) {
	if e.hit_flash.a <= 0 {
		return
	}

	decay := ctx.delta_t / HIT_FLASH_DURATION_SEC
	if e.durability > 0 && e.durability < LOW_DURABILITY_FLASH_THRESHOLD {
		decay *= LOW_DURABILITY_FLASH_DECAY_MULT
	}
	e.hit_flash.a -= decay
	if e.hit_flash.a < 0 {
		e.hit_flash.a = 0
	}
}

entity_apply_hit :: proc(target: ^Entity, hitter: ^Entity) {
	if !is_valid(target^) {
		return
	}

	if target.on_hit_proc != nil {
		target.on_hit_proc(target, hitter)
	}

	if target.durability <= 0 {
		return
	}

	if is_valid(hitter^) && hitter.kind == .player {
		start_player_swing_fx(target.pos.x, true)
	}

	damage := get_hit_durability_damage(hitter)
	if damage > 0 {
		target.hit_flash = Vec4{1, 1, 1, 1}
	}
	target.last_hit_time = now()
	target.durability_regen_accum = 0
	target.durability -= damage
	if target.durability > 0 {
		return
	}

	for i in 0..<target.break_drop_len {
		drop := target.break_drops[i]
		if drop.item == .nil || drop.count <= 0 do continue
		spawn_item_pickup_towards_player(drop.item, drop.count, compute_hit_drop_spawn_pos(target))
	}
	if target.kind == .tree_ent {
		// Tree breaks should always leave a sprout in the world.
		sprout := entity_create(.sprout_ent)
		sprout.pos = target.pos
	}
	if should_roll_bonus_sapling_drop(target.kind) && roll_chance(0.5, u64(target.handle.id)+u64(ctx.gs.ticks)*733) {
		spawn_item_pickup_towards_player(.sapling, 1, compute_hit_drop_spawn_pos(target))
	}
	entity_destroy(target)
}

find_hittable_entity_at_world_pos :: proc(mouse_world: Vec2) -> (^Entity, bool) {
	target, ok := find_entity_at_world_pos(mouse_world)
	if !ok {
		return nil, false
	}
	if !is_valid(target^) {
		return nil, false
	}

	#partial switch target.kind {
	case .player, .item_pickup, .dagger_projectile, .movement_indicator_fx, .grass_ent:
		return nil, false
	}

	return target, true
}

clear_hold_hit_target :: proc() {
	ctx.gs.has_hold_hit_target = false
	ctx.gs.hold_hit_target = {}
}

begin_hold_hit_target_from_mouse :: proc(mouse_world: Vec2) {
	target, ok := find_hittable_entity_at_world_pos(mouse_world)
	if !ok {
		clear_hold_hit_target()
		return
	}

	ctx.gs.has_hold_hit_target = true
	ctx.gs.hold_hit_target = target.handle
}

try_hit_entity_at_mouse :: proc(mouse_world: Vec2) -> (did_hit: bool, hit_handle: Entity_Handle) {
	target, ok := find_hittable_entity_at_world_pos(mouse_world)
	if !ok {
		return false, {}
	}

	player := get_player()
	entity_apply_hit(target, player)
	return true, target.handle
}

update_hold_hit_cycle :: proc() {
	if !key_down(.LEFT_MOUSE) || is_any_ui_overlay_open() {
		clear_hold_hit_target()
		return
	}

	if !ctx.gs.has_hold_hit_target {
		return
	}

	if !is_hit_cooldown_ready() {
		return
	}

	mouse_world := mouse_pos_in_current_space()
	target, ok := find_hittable_entity_at_world_pos(mouse_world)
	if !ok || target.handle.id != ctx.gs.hold_hit_target.id {
		clear_hold_hit_target()
		return
	}

	player := get_player()
	item, _ := get_equipped_item()
	entity_apply_hit(target, player)
	start_hit_cooldown_for_item(item)
	sound_play("event:/schloop", pos=mouse_world)
}

can_player_interact_entity :: proc(player: ^Entity, target: ^Entity) -> bool {
	if !is_valid(player^) || !is_valid(target^) {
		return false
	}
	if player.handle.id == target.handle.id {
		return false
	}

	diff := player.pos - target.pos
	dist_sq := diff.x*diff.x + diff.y*diff.y
	return dist_sq <= INTERACT_RANGE*INTERACT_RANGE
}

interact_entity :: proc(player: ^Entity, target: ^Entity) -> bool {
	if !can_player_interact_entity(player, target) {
		return false
	}

	#partial switch target.kind {
	case .oblisk_ent:
		target.is_active = !target.is_active
		log.infof("oblisk_ent toggled active=%v", target.is_active)
		return true
	}
	return false
}

try_interact_pending_target :: proc(player: ^Entity) {
	if !player.has_pending_interact {
		return
	}

	target, ok := entity_from_handle(player.pending_interact)
	if !ok || !is_valid(target^) {
		player.has_pending_interact = false
		player.pending_interact = {}
		return
	}

	if interact_entity(player, target) {
		player.has_pending_interact = false
		player.pending_interact = {}
	}
}

find_entity_at_world_pos :: proc(pos: Vec2) -> (^Entity, bool) {
	best: ^Entity
	best_sort_y: f32 = -99999999

	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !is_valid(e^) do continue
		if e.kind == .player do continue
		if e.kind == .movement_indicator_fx do continue
		if e.kind == .dagger_projectile do continue
		if e.kind == .grass_ent do continue

		rect, ok := get_entity_hitbox_rect(e^)
		if !ok {
			rect, ok = get_entity_sprite_rect(e^)
			if !ok do continue
		}

		if !shape.rect_contains(rect, pos) do continue

		sort_y := get_entity_sort_y(e^)
		if best == nil || sort_y > best_sort_y {
			best = e
			best_sort_y = sort_y
		}
	}

	return best, best != nil
}

get_nearby_blocker_hitbox :: proc(player_pos: Vec2, within_px: f32) -> (shape.Rect, bool) {
	best_dist := within_px + 0.001
	best := shape.Rect{}
	found := false

	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !is_valid(e^) do continue
		if !e.blocks_player do continue

		hitbox, ok := get_entity_hitbox_rect(e^)
		if !ok do continue

		closest_x := math.clamp(player_pos.x, hitbox.x, hitbox.z)
		closest_y := math.clamp(player_pos.y, hitbox.y, hitbox.w)
		dx := player_pos.x - closest_x
		dy := player_pos.y - closest_y
		dist := math.sqrt(dx*dx + dy*dy)
		if dist <= within_px && dist < best_dist {
			best_dist = dist
			best = hitbox
			found = true
		}
	}

	return best, found
}

compute_detour_around_hitbox :: proc(player_pos: Vec2, final_target: Vec2, blocker: shape.Rect) -> Vec2 {
	margin: f32 = 8
	center := (blocker.xy + blocker.zw) * 0.5
	to_target := final_target - center

	detour := player_pos
	if math.abs(to_target.x) >= math.abs(to_target.y) {
		detour.x = blocker.z + margin if to_target.x >= 0 else blocker.x - margin
		detour.y = math.clamp(player_pos.y, blocker.y - margin, blocker.w + margin)
	} else {
		detour.y = blocker.w + margin if to_target.y >= 0 else blocker.y - margin
		detour.x = math.clamp(player_pos.x, blocker.x - margin, blocker.z + margin)
	}

	// Avoid degenerate tiny moves.
	if linalg.length(detour-player_pos) < 1.0 {
		detour.x += margin
	}

	return detour
}

set_player_move_target_with_detour :: proc(player: ^Entity, target: Vec2) {
	player.queued_move_target = {}
	player.has_queued_move_target = false

	blocker, near_blocker := get_nearby_blocker_hitbox(player.pos, 10)
	if near_blocker {
		detour := compute_detour_around_hitbox(player.pos, target, blocker)
		if !is_world_position_blocked_for_player(detour) {
			player.move_target = detour
			player.has_move_target = true
			player.queued_move_target = target
			player.has_queued_move_target = true
			return
		}
	}

	player.move_target = target
	player.has_move_target = true
}

is_world_position_blocked_for_player :: proc(pos: Vec2) -> bool {
	if is_world_pos_in_locked_area(pos) {
		return true
	}

	if is_world_pos_in_water_collision(pos) {
		return true
	}
	if is_world_pos_in_terrain_block_collision(pos) {
		return true
	}

	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !e.blocks_player do continue

		hitbox, ok := get_entity_hitbox_rect(e^)
		if !ok do continue
		if rounded_hitbox_contains_point(hitbox, pos, HITBOX_CORNER_CUT) {
			return true
		}
	}
	return false
}

is_player_hitbox_blocked_at_pos :: proc(player: ^Entity, pos: Vec2) -> bool {
	probe := player^
	probe.pos = pos
	player_hitbox, ok := get_entity_hitbox_rect(probe)
	if !ok {
		return false
	}

	if is_rect_touching_locked_world_area(player_hitbox) {
		return true
	}

	if is_rect_touching_water_collision(player_hitbox) {
		return true
	}
	if is_rect_touching_terrain_block_collision(player_hitbox) {
		return true
	}

	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !e.blocks_player do continue
		if e.handle.id == player.handle.id do continue

		blocker_hitbox, blocker_ok := get_entity_hitbox_rect(e^)
		if !blocker_ok do continue
		hit, _ := rounded_hitbox_collide_rect(player_hitbox, blocker_hitbox, HITBOX_CORNER_CUT)
		if hit {
			return true
		}
	}

	return false
}

cancel_player_auto_move :: proc(player: ^Entity) {
	player.has_move_target = false
	player.has_queued_move_target = false
	player.queued_move_target = {}
	player.has_pending_interact = false
	player.pending_interact = {}
}

despawn_dagger_projectile :: proc(e: ^Entity) {
	added := inventory_add_item(&ctx.gs.inventory, .dagger_item, 1)
	if added < 1 {
		// If inventory is full, drop it back into the world.
		spawn_item_pickup(.dagger_item, 1, e.pos)
	}
	entity_destroy(e)
}

// note, this needs to be in the game layer because it varies from game to game.
// Specifically, stuff like anim_index and whatnot aren't guarenteed to be named the same or actually even be on the base entity.
// (in terrafactor, it's inside a sub state struct)
draw_entity_default :: proc(e: Entity) {
	e := e // need this bc we can't take a reference from a procedure parameter directly

	if e.sprite == nil {
		return
	}

	xform := utils.xform_rotate(e.rotation)
	entity_col := color.WHITE
	if is_player_behind_entity(e) {
		entity_col.a = 0.3
	}
	draw_flip_x := e.flip_x
	if e.sprite == .player_run {
		// Current run sheet faces opposite direction from idle; normalize facing here.
		draw_flip_x = !draw_flip_x
	}

	if e.hit_flash.a > 0 {
		outline_alpha := e.hit_flash.a
		if e.durability > 0 && e.durability < LOW_DURABILITY_FLASH_THRESHOLD {
			outline_alpha = min(1.0, outline_alpha * LOW_DURABILITY_FLASH_ALPHA_MULT)
		}
		outline_col := Vec4{1, 1, 1, outline_alpha}
		draw_sprite(e.pos + Vec2{1, 0}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
		draw_sprite(e.pos + Vec2{-1, 0}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
		draw_sprite(e.pos + Vec2{0, 1}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
		draw_sprite(e.pos + Vec2{0, -1}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
		if e.durability > 0 && e.durability < LOW_DURABILITY_FLASH_THRESHOLD {
			draw_sprite(e.pos + Vec2{2, 0}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{-2, 0}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{0, 2}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{0, -2}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{1, 1}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{-1, 1}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{1, -1}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
			draw_sprite(e.pos + Vec2{-1, -1}, e.sprite, pivot=e.draw_pivot, flip_x=draw_flip_x, draw_offset=e.draw_offset, xform=xform, anim_index=e.anim_index, col=outline_col, z_layer=.playspace)
		}
	}

	draw_sprite_entity(&e, e.pos, e.sprite, xform=xform, anim_index=e.anim_index, draw_offset=e.draw_offset, flip_x=draw_flip_x, pivot=e.draw_pivot, col=entity_col)
}

// helper for drawing a sprite that's based on an entity.
// useful for systems-based draw overrides, like having the concept of a hit_flash across all entities
draw_sprite_entity :: proc(
	entity: ^Entity,

	pos: Vec2,
	sprite: Sprite_Name,
	pivot:=utils.Pivot.center_center,
	flip_x:=false,
	draw_offset:=Vec2{},
	xform:=Matrix4(1),
	anim_index:=0,
	col:=color.WHITE,
	col_override:Vec4={},
	z_layer:ZLayer={},
	flags:Quad_Flags={},
	params:Vec4={},
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
	z_layer_queue:=-1,
) {

	col_override := col_override

	col_override = entity.scratch.col_override
	if entity.hit_flash.a != 0 {
		col_override.xyz = entity.hit_flash.xyz
		col_override.a = max(col_override.a, entity.hit_flash.a)
	}

	draw_sprite(pos, sprite, pivot, flip_x, draw_offset, xform, anim_index, col, col_override, z_layer, flags, params, crop_top, crop_left, crop_bottom, crop_right)
}

//
// ~ Gameplay Slop Waterline ~
//
// From here on out, it's gameplay slop time.
// Structure beyond this point just slows things down.
//
// No point trying to make things 'reusable' for future projects.
// It's trivially easy to just copy and paste when needed.
//

// shorthand for getting the player
get_player :: proc() -> ^Entity {
	return entity_from_handle(ctx.gs.player_handle)
}

get_equipped_item :: proc() -> (item: Item_Kind, count: int) {
	inv := &ctx.gs.inventory
	if inv.equipped_slot < 0 || inv.equipped_slot >= len(inv.slots) {
		return .nil, 0
	}

	slot := inv.slots[inv.equipped_slot]
	return slot.item, slot.count
}

consume_equipped_item :: proc(count: int) -> bool {
	if count <= 0 {
		return false
	}

	inv := &ctx.gs.inventory
	if inv.equipped_slot < 0 || inv.equipped_slot >= len(inv.slots) {
		return false
	}

	slot := &inv.slots[inv.equipped_slot]
	if slot.item == .nil || slot.count < count {
		return false
	}

	slot.count -= count
	if slot.count <= 0 {
		slot^ = {}
	}

	return true
}

try_throw_equipped_dagger :: proc() {
	if is_any_ui_overlay_open() {
		return
	}

	if !key_pressed(.LEFT_MOUSE) {
		return
	}

	item, count := get_equipped_item()
	if item != .dagger_item || count <= 0 {
		return
	}
	if !is_hit_cooldown_ready() {
		consume_key_pressed(.LEFT_MOUSE)
		return
	}

	player := get_player()
	if !is_valid(player^) {
		return
	}

	target := mouse_pos_in_current_space()
	dir := target - player.pos
	len_sq := dir.x*dir.x + dir.y*dir.y
	if len_sq <= 0.0001 {
		dir = Vec2{player.flip_x ? -1 : 1, 0}
	} else {
		dir /= math.sqrt(len_sq)
	}

	if !consume_equipped_item(1) {
		return
	}

	hand_phase := f32(now()) * 5.0 + f32(player.handle.id) * 0.37
	throw_rot := -45 + math.sin(hand_phase * 0.2) * 8.0

	p := entity_create(.dagger_projectile)
	p.pos = player.pos + Vec2{player.flip_x ? -4 : 4, 20}
	p.vel = dir * 280
	p.max_distance = 200
	p.distance_travelled = 0
	p.flip_x = dir.x < 0
	p.rotation = throw_rot

	start_hit_cooldown_for_item(item)
	consume_key_pressed(.LEFT_MOUSE)
}

set_entity_durability :: proc(e: ^Entity, value: int) {
	e.durability = max(0, value)
	e.durability_max = e.durability
	e.durability_regen_accum = 0
	e.last_hit_time = now()
}

clear_entity_break_drops :: proc(e: ^Entity) {
	e.break_drop_len = 0
	for i in 0..<MAX_BREAK_DROPS {
		e.break_drops[i] = {}
	}
}

add_entity_break_drop :: proc(e: ^Entity, item: Item_Kind, count: int) {
	if item == .nil || count <= 0 {
		return
	}
	if e.break_drop_len >= MAX_BREAK_DROPS {
		return
	}
	e.break_drops[e.break_drop_len] = Break_Drop{item=item, count=count}
	e.break_drop_len += 1
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player
	set_entity_durability(e, 0)
	clear_entity_break_drops(e)
	e.on_hit_proc = entity_on_hit_noop

	// this offset is to take it from the bottom center of the aseprite document
	// and center it at the feet
	e.draw_offset = Vec2{0.5, 5}
	e.draw_pivot = .bottom_center

	e.update_proc = proc(e: ^Entity) {
		move_dir := Vec2{}
		if !is_any_ui_overlay_open() {
			move_dir = get_input_vector()
			if move_dir != {} {
				cancel_player_auto_move(e)
				e.has_pending_place = false
				e.pending_place_item = .nil
				move_step := move_dir * PLAYER_MOVE_SPEED * ctx.delta_t
				next_pos := e.pos + move_step
				if !is_player_hitbox_blocked_at_pos(e, next_pos) {
					e.pos = next_pos
				} else {
					move_dir = {}
				}
			} else if e.has_move_target {
				to_target := e.move_target - e.pos
				dist_sq := to_target.x*to_target.x + to_target.y*to_target.y
				if dist_sq <= 2.0*2.0 {
					if !is_player_hitbox_blocked_at_pos(e, e.move_target) {
						e.pos = e.move_target
						if e.has_queued_move_target {
							e.move_target = e.queued_move_target
							e.has_move_target = true
							e.has_queued_move_target = false
							e.queued_move_target = {}
						} else {
							e.has_move_target = false
							try_interact_pending_target(e)
						}
					} else {
						cancel_player_auto_move(e)
					}
				} else {
					dist := math.sqrt(dist_sq)
					move_dir = to_target / dist
					move_step := move_dir * PLAYER_MOVE_SPEED * ctx.delta_t
					step_len := linalg.length(move_step)
					if step_len > dist {
						if !is_player_hitbox_blocked_at_pos(e, e.move_target) {
							e.pos = e.move_target
							if e.has_queued_move_target {
								e.move_target = e.queued_move_target
								e.has_move_target = true
								e.has_queued_move_target = false
								e.queued_move_target = {}
							} else {
								e.has_move_target = false
								try_interact_pending_target(e)
							}
						} else {
							cancel_player_auto_move(e)
						}
					} else {
						next_pos := e.pos + move_step
						if !is_player_hitbox_blocked_at_pos(e, next_pos) {
							e.pos = next_pos
						} else {
							cancel_player_auto_move(e)
							move_dir = {}
						}
					}
				}
			}
		}
		try_place_pending_item(e)

		if move_dir.x != 0 {
			e.last_known_x_dir = move_dir.x
		}
		e.flip_x = e.last_known_x_dir > 0

		is_moving := move_dir != {}
		if is_moving {
			entity_set_animation(e, .player_run, 0.1)
		} else {
			entity_set_animation(e, .player_idle, 0.3)
		}

	}

	e.draw_proc = proc(e: Entity) {
		draw_sprite(e.pos + Vec2{0, -4}, .shadow_medium, col={1,1,1,0.2})
		draw_entity_default(e)

		if ctx.gs.swing_active && ctx.gs.swing_sprite != .nil {
			swing_dir := ctx.gs.swing_dir
			hand_pos := e.pos + Vec2{0, 8} + swing_dir * 25
			xform := Matrix4(1)
			xform *= utils.xform_rotate(ctx.gs.swing_rotation)
			xform *= utils.xform_scale(Vec2{0.9, 0.9})
			draw_sprite(hand_pos, ctx.gs.swing_sprite, pivot=.center_center, xform=xform, anim_index=ctx.gs.swing_anim_index, z_layer=.playspace)
			return
		}

		equipped_item, equipped_count := get_equipped_item()
		if equipped_item == .dagger_item && equipped_count > 0 {
			hand_x: f32 = 4
			if e.flip_x {
				hand_x = -4
			}

			phase := f32(now()) * 5.0 + f32(e.handle.id) * 0.37
			bob_y := math.sin(phase) * 0.8
			hand_pos := e.pos + Vec2{hand_x, 25 + bob_y}
			rot := -45 + math.sin(phase * 0.2) * 8.0
			xform := Matrix4(1)
			xform *= utils.xform_rotate(rot)
			xform *= utils.xform_scale(Vec2{0.75, 0.75})
			draw_sprite(hand_pos, .dagger_item, pivot=.center_center, flip_x=e.flip_x, xform=xform, z_layer=.playspace)
		}
	}
}

setup_item_pickup :: proc(using e: ^Entity) {
	kind = .item_pickup
	draw_pivot = .center_center
	blocks_player = false
	set_entity_durability(e, 0)
	clear_entity_break_drops(e)
	on_hit_proc = entity_on_hit_noop

	e.update_proc = proc(e: ^Entity) {
		e.sprite = item_icon_sprite(e.pickup_item)

		if e.vel != {} {
			e.pos += e.vel * ctx.delta_t
			drag_mul := max(0.0, 1.0 - ITEM_DROP_BOUNCE_DRAG*ctx.delta_t)
			e.vel *= drag_mul
			if linalg.length(e.vel) < 1.0 {
				e.vel = {}
			}
		}
	}

	e.draw_proc = proc(e: Entity) {
		e0 := e
		phase := f32(now()) * 3.0 + f32(e.handle.id) * 0.31
		bob_y := math.sin(phase) * 1.5
		bob_pos := e.pos + Vec2{0, bob_y}
		xform := utils.xform_scale(Vec2{0.62, 0.62})
		draw_sprite_entity(&e0, bob_pos, e.sprite, xform=xform, anim_index=e.anim_index, draw_offset=e.draw_offset, flip_x=e.flip_x, pivot=e.draw_pivot)

		if e.pickup_count > 1 {
			draw_text(bob_pos + Vec2{0, 10}, fmt.tprintf("%v", e.pickup_count), pivot=.bottom_center, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{0, 0, 0, 0.5})
		}
	}
}

setup_dagger_projectile :: proc(using e: ^Entity) {
	kind = .dagger_projectile
	sprite = .dagger_item_flying
	draw_pivot = .center_center
	blocks_player = false
	set_entity_durability(e, 0)
	clear_entity_break_drops(e)
	on_hit_proc = entity_on_hit_noop
	max_distance = 500
	loop = false
	frame_duration = 0.05
	anim_index = 0
	next_frame_end_time = 0

	e.update_proc = proc(e: ^Entity) {
		step := e.vel * ctx.delta_t
		e.pos += step
		e.distance_travelled += linalg.length(step)
		e.flip_x = e.vel.x < 0

		projectile_hitbox, ok := get_entity_hitbox_rect(e^)
		if !ok {
			despawn_dagger_projectile(e)
			return
		}

		for handle in get_all_ents() {
			other := entity_from_handle(handle)
			if !is_valid(other^) do continue
			if other.handle.id == e.handle.id do continue
			if other.kind == .player do continue
			if other.kind == .item_pickup do continue
			if other.kind == .dagger_projectile do continue

			other_hitbox, ok := get_entity_hitbox_rect(other^)
			if !ok do continue

			hit, _ := rounded_hitbox_collide_rect(projectile_hitbox, other_hitbox, HITBOX_CORNER_CUT)
			if hit {
				despawn_dagger_projectile(e)
				return
			}
		}

		if e.distance_travelled >= e.max_distance {
			despawn_dagger_projectile(e)
			return
		}
	}

	e.draw_proc = proc(e: Entity) {
		e0 := e
		xform := utils.xform_rotate(e.rotation)
		xform *= utils.xform_scale(Vec2{0.7, 0.7})
		draw_sprite_entity(&e0, e.pos, e.sprite, xform=xform, anim_index=e.anim_index, draw_offset=e.draw_offset, flip_x=e.flip_x, pivot=e.draw_pivot)
	}
}

setup_movement_indicator_fx :: proc(using e: ^Entity) {
	kind = .movement_indicator_fx
	sprite = .movement_indicator
	draw_pivot = .center_center
	draw_offset = {}
	blocks_player = false
	set_entity_durability(e, 0)
	clear_entity_break_drops(e)
	on_hit_proc = entity_on_hit_noop
	loop = false
	frame_duration = 0.05
	anim_index = 0
	next_frame_end_time = 0

	e.update_proc = proc(e: ^Entity) {
		frame_count := get_frame_count(e.sprite)
		if !e.loop && e.anim_index >= frame_count-1 && e.next_frame_end_time == 0 {
			entity_destroy(e)
			return
		}
	}

	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

setup_oblisk_ent :: proc(using e: ^Entity) {
	kind = .oblisk_ent
	sprite = .oblisk_rest
	draw_pivot = .bottom_center
	blocks_player = true
	set_entity_durability(e, 800)
	clear_entity_break_drops(e)
	add_entity_break_drop(e, .oblisk_fragment, 1)
	on_hit_proc = entity_on_hit_noop

	e.update_proc = proc(e: ^Entity) {
		player := get_player()
		if !is_any_ui_overlay_open() && is_action_pressed(.interact) {
			consume_action_pressed(.interact)
			_ = interact_entity(player, e)
		}

		if e.is_active {
			e.sprite = .oblisk
		} else {
			e.sprite = .oblisk_rest
		}

		
	}

	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)

		player := get_player()
		diff := player.pos - e.pos
		dist_sq := diff.x*diff.x + diff.y*diff.y
		if dist_sq <= INTERACT_RANGE*INTERACT_RANGE {
			draw_text(e.pos + Vec2{0, 24}, "Press E", pivot=.bottom_center, col={1, 1, 1, 0.75}, drop_shadow_col={0, 0, 0, 0.35})
		}
	}
}

setup_tree_ent :: proc(using e: ^Entity) {
	kind = .tree_ent
	sprite = .tree
	draw_pivot = .bottom_center
	blocks_player = true
	set_entity_durability(e, 16)
	clear_entity_break_drops(e)
	add_entity_break_drop(e, .wood, 2)
	on_hit_proc = entity_on_hit_tree

	e.update_proc = proc(_: ^Entity) {}
	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

setup_sapling_ent :: proc(using e: ^Entity) {
	kind = .sapling_ent
	sprite = .sapling
	draw_pivot = .bottom_center
	blocks_player = true
	set_entity_durability(e, 3)
	clear_entity_break_drops(e)
	add_entity_break_drop(e, .wood, 1)
	on_hit_proc = entity_on_hit_noop
	schedule_entity_growth(e, SAPLING_GROWTH_BASE_SEC, SAPLING_GROWTH_JITTER_SEC, 0x51A9)

	e.update_proc = proc(e: ^Entity) {
		if e.growth_ready_time > 0 && now() >= e.growth_ready_time {
			grow_entity_into_kind(e, .tree_ent)
		}
	}
	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

setup_sprout_ent :: proc(using e: ^Entity) {
	kind = .sprout_ent
	sprite = .sprout
	draw_pivot = .bottom_center
	blocks_player = true
	set_entity_durability(e, 2)
	clear_entity_break_drops(e)
	add_entity_break_drop(e, .fiber, 1)
	on_hit_proc = entity_on_hit_noop
	schedule_entity_growth(e, SPROUT_GROWTH_BASE_SEC, SPROUT_GROWTH_JITTER_SEC, 0x5A70)

	e.update_proc = proc(e: ^Entity) {
		if e.growth_ready_time > 0 && now() >= e.growth_ready_time {
			grow_entity_into_kind(e, .sapling_ent)
		}
	}
	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

setup_grass_ent :: proc(using e: ^Entity) {
	kind = .grass_ent
	sprite = .grass
	draw_pivot = .center_center
	blocks_player = false
	set_entity_durability(e, 0)
	clear_entity_break_drops(e)
	on_hit_proc = entity_on_hit_noop
	loop = true
	frame_duration = 0.12

	frame_count := get_frame_count(sprite)
	if frame_count > 1 {
		anim_index = e.handle.id % frame_count
	} else {
		anim_index = 0
	}

	e.update_proc = proc(_: ^Entity) {}
	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

entity_set_animation :: proc(e: ^Entity, sprite: Sprite_Name, frame_duration: f32, looping:=true) {
	if e.sprite != sprite {
		e.sprite = sprite
		e.loop = looping
		e.frame_duration = frame_duration
		e.anim_index = 0
		e.next_frame_end_time = 0
	}
}
update_entity_animation :: proc(e: ^Entity) {
	if e.frame_duration == 0 do return

	frame_count := get_frame_count(e.sprite)

	is_playing := true
	if !e.loop {
		is_playing = e.anim_index + 1 <= frame_count
	}

	if is_playing {
	
		if e.next_frame_end_time == 0 {
			e.next_frame_end_time = now() + f64(e.frame_duration)
		}
	
		if end_time_up(e.next_frame_end_time) {
			e.anim_index += 1
			e.next_frame_end_time = 0
			//e.did_frame_advance = true
			if e.anim_index >= frame_count {

				if e.loop {
					e.anim_index = 0
				} else {
					e.anim_index = frame_count - 1
				}

			}
		}
	}
}
