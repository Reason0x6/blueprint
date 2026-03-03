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

import sapp "sokol/app"
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
	inventory: Inventory_State,

	scratch: struct {
		all_entities: []Entity_Handle,
	}
}

INVENTORY_SLOT_COUNT :: 12
HOTBAR_SLOT_COUNT :: 6
HOTBAR_SLOT_START :: INVENTORY_SLOT_COUNT - HOTBAR_SLOT_COUNT

Item_Kind :: enum u8 {
	nil,
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
	drag_from_slot: int,
	drag_slot: Inventory_Slot,
}

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
	blocks_player: bool,
	pickup_item: Item_Kind,
	pickup_count: int,
	vel: Vec2,
	max_distance: f32,
	distance_travelled: f32,
	move_target: Vec2,
	has_move_target: bool,
	queued_move_target: Vec2,
	has_queued_move_target: bool,
	pending_interact: Entity_Handle,
	has_pending_interact: bool,
	
	// this gets zeroed every frame. Useful for passing data to other systems.
	scratch: struct {
		col_override: Vec4,
	}
}

Entity_Kind :: enum {
	nil,
	player,
	oblisk_ent,
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
	dagger_item,
	dagger_item_thrown,
	movement_indicator,
	player_death,
	player_run,
	player_idle,
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
	.dagger_item_thrown = {frame_count=7},
	.movement_indicator = {frame_count=6},

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
}

app_frame :: proc() {

	// right now we are just calling the game update, but in future this is where you'd do a big
	// "UX" switch for startup splash, main menu, settings, in-game, etc

	{
		// ui space example
		push_coord_space(get_screen_space())

		x, y := screen_pivot(.top_left)
		x += 2
		y -= 2

		button_pos := Vec2{x, y - 14}
		button_size := Vec2{90, 12}
		button_rect := shape.rect_make(button_pos, button_size, pivot=.top_left)
		hover, pressed := raw_button(button_rect)
		if pressed {
			ctx.gs.debug_show_hitboxes = !ctx.gs.debug_show_hitboxes
		}

		button_col := Vec4{0.05, 0.05, 0.05, 0.7}
		if hover {
			button_col = Vec4{0.2, 0.2, 0.2, 0.8}
		}
		draw_rect(button_rect, col=button_col, outline_col=Vec4{1, 1, 1, 0.45}, z_layer=.ui)

		button_label := ctx.gs.debug_show_hitboxes ? "Hitboxes: ON" : "Hitboxes: OFF"
		draw_text(button_pos + Vec2{2, -2}, button_label, z_layer=.ui, pivot=.top_left, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{})

		overlap_button_pos := button_pos + Vec2{0, -14}
		overlap_button_rect := shape.rect_make(overlap_button_pos, button_size, pivot=.top_left)
		overlap_hover, overlap_pressed := raw_button(overlap_button_rect)
		if overlap_pressed {
			ctx.gs.debug_show_overlap_boxes = !ctx.gs.debug_show_overlap_boxes
		}

		overlap_button_col := Vec4{0.05, 0.05, 0.05, 0.7}
		if overlap_hover {
			overlap_button_col = Vec4{0.2, 0.2, 0.2, 0.8}
		}
		draw_rect(overlap_button_rect, col=overlap_button_col, outline_col=Vec4{1, 1, 1, 0.45}, z_layer=.ui)

		overlap_button_label := ctx.gs.debug_show_overlap_boxes ? "Overlap: ON" : "Overlap: OFF"
		draw_text(overlap_button_pos + Vec2{2, -2}, overlap_button_label, z_layer=.ui, pivot=.top_left, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{})

		draw_inventory_ui()
	}

	sound_play_continuously("event:/ambiance", "")

	game_update()
	game_draw()

	volume :f32= 0.75
	sound_update(get_player().pos, volume)
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

	// setup world for first game tick
	if ctx.gs.ticks == 0 {
		player := entity_create(.player)
		ctx.gs.player_handle = player.handle
		ctx.gs.inventory.equipped_slot = HOTBAR_SLOT_START

		oblisk := entity_create(.oblisk_ent)
		oblisk.pos = Vec2{64, 0}

		spawn_item_pickup(.dagger_item, 1, Vec2{-55, 6})
		
	}

	rebuild_scratch_helpers()
	
	// big :update time
	for handle in get_all_ents() {
		e := entity_from_handle(handle)

		update_entity_animation(e)

		if e.update_proc != nil {
			e.update_proc(e)
		}
	}

	resolve_player_vs_hitboxes()
	inventory_update()
	try_throw_equipped_dagger()

	if key_pressed(.RIGHT_MOUSE) {
		consume_key_pressed(.RIGHT_MOUSE)

		player := get_player()
		if is_valid(player^) {
			target := mouse_pos_in_current_space()
			clicked_entity, clicked_entity_ok := find_entity_at_world_pos(target)
			if clicked_entity_ok {
				set_player_move_target_with_detour(player, clicked_entity.pos)
				player.pending_interact = clicked_entity.handle
				player.has_pending_interact = true
				spawn_movement_indicator(target)
			} else if !is_world_position_blocked_for_player(target) {
				set_player_move_target_with_detour(player, target)
				player.has_pending_interact = false
				player.pending_interact = {}
				spawn_movement_indicator(target)
			}
		}
	}

	if key_pressed(.LEFT_MOUSE) {
		consume_key_pressed(.LEFT_MOUSE)

		pos := mouse_pos_in_current_space()
		log.info("schloop at", pos)
		sound_play("event:/schloop", pos=pos)
	}

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

			hit, push := shape.collide(player_hitbox, blocker_hitbox)
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
	case .oblisk_fragment: return "Fragment"
	case .oblisk_core: return "Core"
	case .dagger_item: return "Dagger"
	case: return ""
	}
}

item_icon_sprite :: proc(item: Item_Kind) -> Sprite_Name {
	switch item {
	case .nil: return .nil
	case .oblisk_fragment: return .oblisk_broken
	case .oblisk_core: return .oblisk
	case .dagger_item: return .dagger_item
	case: return .nil
	}
}

item_max_stack :: proc(item: Item_Kind) -> int {
	switch item {
	case .nil: return 0
	case .oblisk_fragment: return 99
	case .oblisk_core: return 10
	case .dagger_item: return 1
	case: return 0
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

inventory_update :: proc() {
	inv := &ctx.gs.inventory

	if key_pressed(.TAB) {
		consume_key_pressed(.TAB)
		inv.open = !inv.open
	}

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
	pickup_range_sq :f32= 40.0 * 40.0
	picked_any := false
	for handle in get_all_ents() {
		e := entity_from_handle(handle)
		if e.kind != .item_pickup do continue

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

hotbar_slot_rect :: proc(i: int) -> shape.Rect {
	cx, by := screen_pivot(.bottom_center)
	slot_size := Vec2{22, 22}
	gap: f32 = 3
	total_w := f32(HOTBAR_SLOT_COUNT)*slot_size.x + f32(HOTBAR_SLOT_COUNT-1)*gap
	start := Vec2{cx - total_w*0.5, by + 4}
	pos := start + Vec2{f32(i) * (slot_size.x + gap), 0}
	return shape.rect_make(pos, slot_size, pivot=.bottom_left)
}

inventory_grid_slot_rect :: proc(i: int) -> shape.Rect {
	cx, cy := screen_pivot(.center_center)
	panel_size := Vec2{170, 76}
	panel := shape.rect_make(Vec2{cx, cy + 20}, panel_size, pivot=.center_center)

	cols :: 6
	slot_size := Vec2{22, 22}
	gap: f32 = 3
	grid_start := Vec2{panel.x + 8, panel.y + 8}

	col := i % cols
	row := i / cols
	pos := grid_start + Vec2{f32(col) * (slot_size.x + gap), f32(1-row) * (slot_size.y + gap)}
	return shape.rect_make(pos, slot_size, pivot=.bottom_left)
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

clear_inventory_drag :: proc(inv: ^Inventory_State) {
	inv.dragging = false
	inv.drag_from_slot = -1
	inv.drag_slot = {}
}

drop_dragged_slot :: proc(inv: ^Inventory_State, drop_index: int, drop_ok: bool) {
	if !inv.dragging || inv.drag_slot.item == .nil || inv.drag_slot.count <= 0 {
		clear_inventory_drag(inv)
		return
	}

	from := inv.drag_from_slot
	drag := inv.drag_slot
	target_index := drop_index

	if !drop_ok || target_index < 0 || target_index >= INVENTORY_SLOT_COUNT {
		target_index = from
	}

	if target_index == from {
		inv.slots[from] = drag
		clear_inventory_drag(inv)
		return
	}

	dst := &inv.slots[target_index]
	if dst.item == .nil || dst.count <= 0 {
		dst^ = drag
		clear_inventory_drag(inv)
		return
	}

	if dst.item == drag.item {
		max_stack := item_max_stack(drag.item)
		free := max(0, max_stack - dst.count)
		to_add := min(free, drag.count)
		dst.count += to_add
		remaining := drag.count - to_add

		if remaining > 0 {
			inv.slots[from] = {item=drag.item, count=remaining}
		}

		clear_inventory_drag(inv)
		return
	}

	// Swap with destination item.
	tmp := dst^
	dst^ = drag
	inv.slots[from] = tmp
	clear_inventory_drag(inv)
}

draw_inventory_ui :: proc() {
	inv := &ctx.gs.inventory
	mouse_pos := mouse_pos_in_current_space()

	if key_pressed(.LEFT_MOUSE) {
		slot_index, slot_ok := find_inventory_slot_at_mouse(inv, mouse_pos)
		if slot_ok && !inv.dragging {
			inv.equipped_slot = slot_index
			slot := &inv.slots[slot_index]
			if slot.item != .nil && slot.count > 0 {
				inv.dragging = true
				inv.drag_from_slot = slot_index
				inv.drag_slot = slot^
				slot^ = {}
			}
			consume_key_pressed(.LEFT_MOUSE)
		}
	}

	if key_released(.LEFT_MOUSE) && inv.dragging {
		slot_index, slot_ok := find_inventory_slot_at_mouse(inv, mouse_pos)
		if slot_ok {
			drop_dragged_slot(inv, slot_index, slot_ok)
		} else {
			if inv.drag_slot.item != .nil && inv.drag_slot.count > 0 {
				drop_pos := mouse_pos_in_world_space()
				spawn_item_pickup(inv.drag_slot.item, inv.drag_slot.count, drop_pos)
			}
			clear_inventory_drag(inv)
		}
		consume_key_released(.LEFT_MOUSE)
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
		draw_text(Vec2{cx, by + 29}, label, pivot=.bottom_center, z_layer=.ui, col=Vec4{1, 1, 1, 0.8}, drop_shadow_col=Vec4{})
	}

	if !inv.open {
		return
	}

	// Full inventory panel
	{
		cx, cy := screen_pivot(.center_center)
		panel_size := Vec2{170, 76}
		panel := shape.rect_make(Vec2{cx, cy + 20}, panel_size, pivot=.center_center)
		draw_rect(panel, col=Vec4{0.02, 0.02, 0.02, 0.9}, outline_col=Vec4{1, 1, 1, 0.25}, z_layer=.ui)
		draw_text(Vec2{panel.x + 6, panel.w - 4}, "Inventory [TAB]", pivot=.top_left, z_layer=.ui, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{})

		for i in 0..<INVENTORY_SLOT_COUNT {
			rect := inventory_grid_slot_rect(i)
			hover := shape.rect_contains(rect, mouse_pos)
			draw_inventory_slot(rect, inv.slots[i], selected=inv.equipped_slot == i, hover=hover)
		}
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
	e.sprite = item_icon_sprite(item)
	return e
}

spawn_movement_indicator :: proc(pos: Vec2) -> ^Entity {
	e := entity_create(.movement_indicator_fx)
	e.pos = pos
	return e
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
	return dist_sq <= 40*40
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
		if shape.rect_contains(hitbox, pos) {
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

	draw_sprite_entity(&e, e.pos, e.sprite, xform=xform, anim_index=e.anim_index, draw_offset=e.draw_offset, flip_x=e.flip_x, pivot=e.draw_pivot, col=entity_col)
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
	if !key_pressed(.LEFT_MOUSE) {
		return
	}

	item, count := get_equipped_item()
	if item != .dagger_item || count <= 0 {
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

	consume_key_pressed(.LEFT_MOUSE)
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player

	// this offset is to take it from the bottom center of the aseprite document
	// and center it at the feet
	e.draw_offset = Vec2{0.5, 5}
	e.draw_pivot = .bottom_center

	e.update_proc = proc(e: ^Entity) {
		move_dir := get_input_vector()
		if move_dir != {} {
			e.has_move_target = false
			e.has_queued_move_target = false
			e.queued_move_target = {}
			e.has_pending_interact = false
			e.pending_interact = {}
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

		if move_dir.x != 0 {
			e.last_known_x_dir = move_dir.x
		}
		e.flip_x = e.last_known_x_dir < 0

		is_moving := move_dir != {}
		if is_moving {
			entity_set_animation(e, .player_run, 0.1)
		} else {
			entity_set_animation(e, .player_idle, 0.3)
		}

		e.scratch.col_override = Vec4{0,0,1,0.2}
	}

	e.draw_proc = proc(e: Entity) {
		draw_sprite(e.pos, .shadow_medium, col={1,1,1,0.2})
		draw_entity_default(e)

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

	e.update_proc = proc(e: ^Entity) {
		e.sprite = item_icon_sprite(e.pickup_item)
	}

	e.draw_proc = proc(e: Entity) {
		e0 := e
		phase := f32(now()) * 3.0 + f32(e.handle.id) * 0.31
		bob_y := math.sin(phase) * 1.5
		bob_pos := e.pos + Vec2{0, bob_y}
		xform := utils.xform_scale(Vec2{0.55, 0.55})
		draw_sprite_entity(&e0, bob_pos, e.sprite, xform=xform, anim_index=e.anim_index, draw_offset=e.draw_offset, flip_x=e.flip_x, pivot=e.draw_pivot)

		if e.pickup_count > 1 {
			draw_text(bob_pos + Vec2{0, 10}, fmt.tprintf("%v", e.pickup_count), pivot=.bottom_center, col=Vec4{1, 1, 1, 0.9}, drop_shadow_col=Vec4{0, 0, 0, 0.5})
		}
	}
}

setup_dagger_projectile :: proc(using e: ^Entity) {
	kind = .dagger_projectile
	sprite = .dagger_item_thrown
	draw_pivot = .center_center
	blocks_player = false
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

			hit, _ := shape.collide(projectile_hitbox, other_hitbox)
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

	e.update_proc = proc(e: ^Entity) {
		player := get_player()
		if is_action_pressed(.interact) {
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
		if dist_sq <= 40*40 {
			draw_text(e.pos + Vec2{0, 14}, "Press E", pivot=.bottom_center, col={1, 1, 1, 0.75}, drop_shadow_col={0, 0, 0, 0.35})
		}
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
