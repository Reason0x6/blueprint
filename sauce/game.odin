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
	debug_show_grid: bool,
	hold_hit_target: Entity_Handle,
	has_hold_hit_target: bool,
	hit_cooldown_end_time: f64,
	hit_cooldown_duration: f64,
	bg_use_forest_grass: bool,
	ui_overlay_mask: u32,
	swing_active: bool,
	swing_sprite: Sprite_Name,
	swing_anim_index: int,
	swing_next_frame_end_time: f64,
	swing_rotation: f32,
	swing_dir: Vec2,
	inventory: Inventory_State,

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
HITBOX_CORNER_CUT: f32 : 3
TREE_WOOD_HIT_DROP_CHANCE: f32 : 0.15
DURABILITY_REGEN_DELAY_SEC: f64 : 0.5
DURABILITY_REGEN_PER_SEC: f32 : 2.0
ITEM_DROP_BOUNCE_SPEED: f32 : 95
ITEM_DROP_BOUNCE_DRAG: f32 : 6.5
ITEM_DROP_PICKUP_DELAY_SEC: f64 : 0.25
HIT_FLASH_DURATION_SEC: f32 : 0.12
HIT_DROP_MAX_FROM_EDGE: f32 : 40
LOW_DURABILITY_FLASH_THRESHOLD :: 3
LOW_DURABILITY_FLASH_ALPHA_MULT: f32 : 2.0
LOW_DURABILITY_FLASH_DECAY_MULT: f32 : 0.45

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
}

CRAFT_INPUT_COLS :: 2
CRAFT_INPUT_ROWS :: 3
CRAFT_INPUT_SLOT_COUNT :: CRAFT_INPUT_COLS * CRAFT_INPUT_ROWS

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
	break_drop_item: Item_Kind,
	break_drop_count: int,
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
		case .oblisk_ent: setup_oblisk_ent(e) // for now, just use the same setup as the normal oblisk ent
		case .tree_ent: setup_tree_ent(e)
		case .sapling_ent: setup_sapling_ent(e)
		case .sprout_ent: setup_sprout_ent(e)
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
	.sprout = {overlap_box_size=Vec2{10, 8}, overlap_box_offset=Vec2{0, -6}, overlap_box_pivot=.bottom_center},
	.sapling = {overlap_box_size=Vec2{16, 14}, overlap_box_offset=Vec2{0, -10}, overlap_box_pivot=.bottom_center},
	.tree = {overlap_box_size=Vec2{48, 103}, overlap_box_offset=Vec2{0, -51}, overlap_box_pivot=.bottom_center},

	.oblisk = {overlap_box_size=Vec2{12, 22}, overlap_box_offset=Vec2{0, -24}, overlap_box_pivot=.bottom_center},
	.oblisk_rest = {overlap_box_size=Vec2{12, 22}, overlap_box_offset=Vec2{0, -24}, overlap_box_pivot=.bottom_center},
	.oblisk_broken = {overlap_box_size=Vec2{12, 12}, overlap_box_offset=Vec2{0, -20}, overlap_box_pivot=.bottom_center},
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
	panel_size := Vec2{190, 142}
	panel := shape.rect_make(Vec2{cx, cy}, panel_size, pivot=.center_center)
	draw_rect(panel, col=Vec4{0.02, 0.02, 0.02, 0.92}, outline_col=Vec4{1, 1, 1, 0.3}, z_layer=.pause_menu)
	draw_text(Vec2{cx, cy + 52}, "Paused", pivot=.center_center, z_layer=.pause_menu, col=Vec4{1, 1, 1, 0.95}, drop_shadow_col=Vec4{})

	button_size := Vec2{78, 18}
	resume_rect := shape.rect_make(Vec2{cx, cy + 24}, button_size, pivot=.center_center)
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
	debug_start := Vec2{cx, cy - 2}

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
		ctx.gs.bg_use_forest_grass = roll_chance(1.0/3.0, 0xB16B00B5)
		ctx.gs.debug_show_grid = true

		oblisk := entity_create(.oblisk_ent)
		oblisk.pos = Vec2{64, 0}
		tree := entity_create(.tree_ent)
		tree.pos = Vec2{26, 0}
		sapling := entity_create(.sapling_ent)
		sapling.pos =Vec2{-40, 0}
		sprout := entity_create(.sprout_ent)
		sprout.pos = Vec2{-80, 0}

		spawn_item_pickup(.wood, 4, Vec2{-68, 8})
		spawn_item_pickup(.stone, 3, Vec2{-86, 8})
		spawn_item_pickup(.fiber, 4, Vec2{-104, 8})
		spawn_item_pickup(.stone_multitool, 1, Vec2{-55, 6})
		
	}

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

	utils.animate_to_target_v2(&ctx.gs.cam_pos, get_player().pos, ctx.delta_t, rate=10)

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
	bg_sprite := Sprite_Name.bg_repeat_tex0
	if ctx.gs.bg_use_forest_grass {
		bg_sprite = .forest_grass_texture
	}
	draw_frame.bg_repeat_tex0_atlas_uv = atlas_uv_from_sprite(bg_sprite)

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
		if ctx.gs.debug_show_grid {
			draw_world_grid()
		}
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

		draw_player_hit_cooldown_bar()
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

	mouse_world := mouse_pos_in_current_space()
	_, hit_ok := find_hittable_entity_at_world_pos(mouse_world)
	if hit_ok {
		return
	}

	place_pos := snap_vec2_to_grid(mouse_world, ENTITY_GRID_SIZE)
	diff := place_pos - player.pos
	d2 := diff.x*diff.x + diff.y*diff.y
	if d2 > PLACE_PREVIEW_RANGE*PLACE_PREVIEW_RANGE {
		return
	}

	col := Vec4{1, 1, 1, 0.35}
	if is_world_position_blocked_for_player(place_pos) {
		col = Vec4{1, 0.25, 0.25, 0.28}
	}
	draw_sprite(place_pos, sprite, pivot=.center_center, col=col, z_layer=.vfx)
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

	draw_rect(hitbox, col=Vec4{0, 0, 0, 0}, outline_col=Vec4{1, 0.2, 0.2, 0.95}, z_layer=.top)
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

	#partial switch e.kind {
	case .oblisk_ent:
		size := get_sprite_size(e.sprite)
		return shape.rect_make(e.pos + Vec2{0, -4}, Vec2{size.x-6, size.y/2}, pivot=.bottom_center), true
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
		center := e.pos + Vec2{0, -24}

		return shape.rect_make(center, Vec2{size.x-2,size.y/3}, pivot=.bottom_center), true
	case .tree_ent:
		// Tree collider is only the trunk section so players can overlap canopy.
		size := get_sprite_size(e.sprite)
		center := e.pos + Vec2{0, -51}
		return shape.rect_make(center, Vec2{50, 30}, pivot=.bottom_center), true
	case .sapling_ent:
		return shape.rect_make(e.pos + Vec2{0, -13}, Vec2{18, 13}, pivot=.bottom_center), true
	case .sprout_ent:
		return shape.rect_make(e.pos + Vec2{0, -8}, Vec2{15, 10}, pivot=.bottom_center), true
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
	case .player, .item_pickup, .dagger_projectile, .movement_indicator_fx:
		return false
	case:
		return true
	}
}

apply_entity_grid_snap :: proc() {
	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if !should_grid_snap_entity(e^) do continue
		e.pos = snap_vec2_to_grid(e.pos, ENTITY_GRID_SIZE)
	}
}

resolve_player_vs_hitboxes :: proc() {
	player := get_player()
	if !is_valid(player^) {
		return
	}

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

inventory_update :: proc() {
	inv := &ctx.gs.inventory

	if key_pressed(.TAB) {
		consume_key_pressed(.TAB)
		next_open := !is_ui_overlay_open(UI_OVERLAY_INVENTORY)
		if !next_open && inv.open && inv.dragging && inv.drag_slot.item != .nil && inv.drag_slot.count > 0 {
			drop_pos := get_inventory_drop_world_pos(mouse_pos_in_world_space())
			spawn_item_pickup(inv.drag_slot.item, inv.drag_slot.count, drop_pos)
			clear_inventory_drag(inv)
		}
		inv.open = next_open
		set_ui_overlay_open(UI_OVERLAY_INVENTORY, next_open)
	}

	if !inv.open && inv.dragging && inv.drag_slot.item != .nil && inv.drag_slot.count > 0 {
		drop_pos := get_inventory_drop_world_pos(mouse_pos_in_world_space())
		spawn_item_pickup(inv.drag_slot.item, inv.drag_slot.count, drop_pos)
		clear_inventory_drag(inv)
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
				slot := &inv.slots[slot_index]
				if inv.dragging {
					_ = place_held_stack_swap(inv, slot)
				} else {
					_ = pick_up_slot_into_hand(inv, slot, .inventory, slot_index)
				}
				consumed_click = true
			}
		}

		if consumed_click {
			consume_key_pressed(.LEFT_MOUSE)
		}
	}

	if key_pressed(.RIGHT_MOUSE) && inv.dragging {
		consumed_click := false
		slot_index, slot_ok := find_inventory_slot_at_mouse(inv, mouse_pos)
		if slot_ok {
			inv.equipped_slot = slot_index
			_ = place_held_one(inv, &inv.slots[slot_index])
			consumed_click = true
		} else {
			craft_i, craft_ok := find_crafting_input_slot_at_mouse(inv, mouse_pos)
			if craft_ok {
				_ = place_held_one(inv, &inv.crafting_slots[craft_i])
				update_crafting_output(inv)
				consumed_click = true
			}
		}
		if consumed_click {
			consume_key_pressed(.RIGHT_MOUSE)
		}
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

	place_pos := snap_vec2_to_grid(mouse_world, ENTITY_GRID_SIZE)
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

	if target.break_drop_item != .nil && target.break_drop_count > 0 {
		spawn_item_pickup_towards_player(target.break_drop_item, target.break_drop_count, compute_hit_drop_spawn_pos(target))
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
	case .player, .item_pickup, .dagger_projectile, .movement_indicator_fx:
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

setup_player :: proc(e: ^Entity) {
	e.kind = .player
	set_entity_durability(e, 0)
	e.break_drop_item = .nil
	e.break_drop_count = 0
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
				e.has_move_target = false
				e.has_queued_move_target = false
				e.queued_move_target = {}
				e.has_pending_interact = false
				e.pending_interact = {}
				e.has_pending_place = false
				e.pending_place_item = .nil
				e.pos += move_dir * 100.0 * ctx.delta_t
			} else if e.has_move_target {
				to_target := e.move_target - e.pos
				dist_sq := to_target.x*to_target.x + to_target.y*to_target.y
				if dist_sq <= 2.0*2.0 {
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
					dist := math.sqrt(dist_sq)
					move_dir = to_target / dist
					move_step := move_dir * 100.0 * ctx.delta_t
					step_len := linalg.length(move_step)
					if step_len > dist {
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
						e.pos += move_step
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
	break_drop_item = .nil
	break_drop_count = 0
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
	break_drop_item = .nil
	break_drop_count = 0
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
	break_drop_item = .nil
	break_drop_count = 0
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
	draw_pivot = .center_center
	blocks_player = true
	set_entity_durability(e, 800)
	break_drop_item = .oblisk_fragment
	break_drop_count = 1
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
			draw_text(e.pos + Vec2{0, 14}, "Press E", pivot=.bottom_center, col={1, 1, 1, 0.75}, drop_shadow_col={0, 0, 0, 0.35})
		}
	}
}

setup_tree_ent :: proc(using e: ^Entity) {
	kind = .tree_ent
	sprite = .tree
	draw_pivot = .center_center
	blocks_player = true
	set_entity_durability(e, 16)
	break_drop_item = .wood
	break_drop_count = 2
	on_hit_proc = entity_on_hit_tree

	e.update_proc = proc(_: ^Entity) {}
	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

setup_sapling_ent :: proc(using e: ^Entity) {
	kind = .sapling_ent
	sprite = .sapling
	draw_pivot = .center_center
	blocks_player = true
	set_entity_durability(e, 3)
	break_drop_item = .wood
	break_drop_count = 1
	on_hit_proc = entity_on_hit_noop

	e.update_proc = proc(_: ^Entity) {}
	e.draw_proc = proc(e: Entity) {
		draw_entity_default(e)
	}
}

setup_sprout_ent :: proc(using e: ^Entity) {
	kind = .sprout_ent
	sprite = .sprout
	draw_pivot = .center_center
	blocks_player = true
	set_entity_durability(e, 2)
	break_drop_item = .fiber
	break_drop_count = 1
	on_hit_proc = entity_on_hit_noop

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
