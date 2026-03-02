/*

This is just a big dump of random helpers.

It needs to be in a package, because it's helpful to share across projects or other packages.
Like the build.odin for example.

*/
#+feature using-stmt

package utils

import uuid "core:encoding/uuid"
import "core:path/filepath"
import "core:math/linalg/hlsl"
import "core:os"
import "base:intrinsics"
import "base:runtime"
import "base:builtin"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:math/ease"
import "core:time"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:unicode"

// these are just shorthand defs
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Matrix4 :: linalg.Matrix4f32;
Vec2i :: [2]int

Pivot :: enum {
	bottom_left,
	bottom_center,
	bottom_right,
	center_left,
	center_center,
	center_right,
	top_left,
	top_center,
	top_right,
}

Justify_X :: enum {
	left,
	center,
	right,
}
Justify_Y :: enum {
	top,
	center,
	bottom,
}

Axis2 :: enum {
	x,
	y,
}

break_pivot_into_axes :: proc(pivot: Pivot) -> (x: Justify_X, y: Justify_Y) {
	switch pivot {
		case .bottom_left: return .left, .bottom
		case .bottom_center: return .center, .bottom
		case .bottom_right: return .right, .bottom
		case .center_left: return .left, .center
		case .center_center: return .center, .center
		case .center_right: return .right, .center
		case .top_left: return .left, .top
		case .top_center: return .center, .top
		case .top_right: return .right, .top
	}

	crash("uh oh")
	return nil, nil
}

pivot_from_axes :: proc(x: Justify_X, y: Justify_Y) -> Pivot {
	if y == .bottom && x == .center {
		return .bottom_center
	} else if y == .center && x == .center {
		return .center_center
	} else if y == .top && x == .center {
		return .top_center
	} else if y == .bottom && x == .left {
		return .bottom_left
	} else if y == .center && x == .left {
		return .center_left
	} else if y == .top && x == .left {
		return .top_left
	} else if y == .bottom && x == .right {
		return .bottom_right
	} else if y == .center && x == .right {
		return .center_right
	} else if y == .top && x == .right {
		return .top_right
	}

	crash("invalid justify combination")
	return .center_center
}

Direction :: enum {
	north,
	east,
	south,
	west,
}

inverse_direction :: proc(dir: Direction) -> Direction {
	switch dir {
		case .north: return .south
		case .east: return .west
		case .south: return .north
		case .west: return .east
	}

	crash("this shouldn't be hit lol")
	return .north
}

is_direction_parallel :: proc(a: Direction, b: Direction) -> bool {
	a_dir := cardinal_direction_offset_enum(a)
	b_dir := cardinal_direction_offset_enum(a)
	return math.abs(a_dir.x) == math.abs(b_dir.x) && math.abs(a_dir.y) == math.abs(b_dir.y)
}

scale_from_pivot :: proc(pivot: Pivot) -> Vec2 {
	switch pivot {
		case .bottom_left: return Vec2{0.0, 0.0}
		case .bottom_center: return Vec2{0.5, 0.0}
		case .bottom_right: return Vec2{1.0, 0.0}
		case .center_left: return Vec2{0.0, 0.5}
		case .center_center: return Vec2{0.5, 0.5}
		case .center_right: return Vec2{1.0, 0.5}
		case .top_center: return Vec2{0.5, 1.0}
		case .top_left: return Vec2{0.0, 1.0}
		case .top_right: return Vec2{1.0, 1.0}
	}
	return {};
}

vector_from_direction :: proc(dir: Direction) -> Vec2 {
	return Vec2{ f32(cardinal_direction_offset(int(dir)).x), f32(cardinal_direction_offset(int(dir)).y) }
}

direction_from_vector :: proc(vec: Vec2) -> Direction {
	if math.abs(vec.x) > math.abs(vec.y) {
		// X component is dominant
		return vec.x > 0 ? .east : .west
	} else {
		// Y component is dominant (or equal)
		return vec.y > 0 ? .north : .south
	}
}

cardinal_direction_offset :: proc {
	cardinal_direction_offset_enum,
	cardinal_direction_offset_int,
}

cardinal_direction_offset_enum :: proc(dir: Direction) -> Vec2i {
	return cardinal_direction_offset_int(int(dir))
}

// takes in 0..<4 (0,1,2,3) will panic otherwise
cardinal_direction_offset_int :: proc(i: int) -> Vec2i {
	switch i {
		case 0: return {0, 1} // north
		case 1: return {1, 0} // east
		case 2: return {0, -1} // south
		case 3: return {-1, 0} // west
		case:
		log.error("unknown direction", i)
		return {}
	}
}

rotation_from_direction :: proc(dir: Direction) -> f32 {
	switch dir {
		case .north: return 90
		case .east: return 0
		case .south: return 270
		case .west: return 180
	}
	return 0
}

fire :: proc(cmd: ..string) -> os.Error {
	process, start_err := os.process_start(os.Process_Desc{
		command=cmd,
		stdout = os.stdout,
		stderr = os.stderr,
	})
	if start_err != nil {
		fmt.eprintln("Error:", start_err) 
		return start_err
	}

	_, wait_err := os.process_wait(process)
	if wait_err != nil {
		fmt.eprintln("Error:", wait_err) 
		return wait_err
	}

	return nil
}

copy_directory :: proc(dest_dir: string, src_dir: string) {
	file_infos, err := os.read_all_directory_by_path(src_dir, context.temp_allocator)
	if err != nil {
		log.error(err)
		return
	}
	make_directory_if_not_exist(dest_dir)
	for fi in file_infos {
		src_path, src_path_err := filepath.join({src_dir, fi.name}, context.temp_allocator)
		if src_path_err != nil {
			log.error(src_path_err)
			continue
		}
		dest_path, dest_path_err := filepath.join({dest_dir, fi.name}, context.temp_allocator)
		if dest_path_err != nil {
			log.error(dest_path_err)
			continue
		}

		if fi.type == .Directory {
			copy_directory(dest_path, src_path)
		} else {
			os.copy_file(dest_path, src_path)
		}
	}
}

copy_dynamic_array :: proc(dest: ^$T/[dynamic]$E, src: T) {
	clear(dest)
	resize(dest, len(src))
	copy(dest[:], src[:])
}

crash_when_debug :: proc(args: ..any) {
	when ODIN_DEBUG {
		log.error(..args)
		runtime.trap()
	}
}

make_directory_if_not_exist :: proc(path: string) {
	if !os.exists(path) {
		err := os.make_directory_all(path)
		if err != nil {
			log.error(err)
		}
	}
}

pct_chance :: proc(pct: f32) -> bool {
	return rand.float32() < pct
}

random_sign :: proc() -> f32 {
	return rand.int_max(2) == 0 ? 1.0 : -1.0
}

random_dir :: proc() -> Vec2 {
	return linalg.normalize(Vec2{ rand.float32_range(-1, 1), rand.float32_range(-1, 1) })
}

random_cardinal_dir_offset :: proc() -> Vec2i {
	return { rand_int(2)-1, rand_int(2)-1 }
}

append_if_not_exist :: proc(array: ^$T/[dynamic]$E, #no_broadcast arg: E) -> bool {
	for existing in array {
		if existing == arg {
			return false
		}
	}
	append(array, arg)
	return true
}

append_if_not_exist_hack :: proc(array: ^$T/[dynamic]$E, #no_broadcast arg: E) -> bool {
	// #hacky asf
	arg := arg
	for &existing in array {
		if runtime.memory_compare(&existing, &arg, size_of(E)) == 0 {
			return false
		}
	}
	append(array, arg)
	return true
}

snake_case_to_pretty_name :: proc(snake: string) -> string {
	using runtime
	name :Raw_String= transmute(Raw_String) fmt.aprint(snake, allocator=context.temp_allocator);
	for it in 0..<name.len
	{
		c := &name.data[it];
		if c^ == '_'
		{
			c^ = ' ';
			first_letter := &name.data[it+1];
			first_letter^ = u8(unicode.to_upper(rune(first_letter^)));
		}
	}
	if name.len > 0
	{
		name.data[0] = u8(unicode.to_upper(rune(name.data[0])));
	}
	return transmute(string)name;
}

xform_translate :: proc(pos: Vec2) -> Matrix4 {
	return linalg.matrix4_translate(Vec3{pos.x, pos.y, 0})
}
xform_rotate :: proc(angle: f32) -> Matrix4 {
	return linalg.matrix4_rotate(math.to_radians(angle), Vec3{0,0,1})
}
xform_scale :: proc(scale: Vec2) -> Matrix4 {
	return linalg.matrix4_scale(Vec3{scale.x, scale.y, 1});
}

sine_breathe_alpha :: proc(p: $T) -> T where intrinsics.type_is_float(T) {
	return (math.sin((p - .25) * 2.0 * math.PI) / 2.0) + 0.5
}

animate_to_target_f32 :: proc(value: ^f32, target: f32, delta_t: f32, rate:f32= 15.0, good_enough:f32= 0.001) -> bool
{
	value^ += (target - value^) * (1.0 - math.pow_f32(2.0, -rate * delta_t));
	if almost_equals(value^, target, good_enough)
	{
		value^ = target;
		return true; // reached
	}
	return false;
}

animate_to_target_v2 :: proc(value: ^Vec2, target: Vec2, delta_t: f32, rate :f32= 15.0, good_enough:f32= 0.001) -> bool {
	x_reached := animate_to_target_f32(&value.x, target.x, delta_t, rate, good_enough)
	y_reached := animate_to_target_f32(&value.y, target.y, delta_t, rate, good_enough)
	return x_reached && y_reached
}

almost_equals :: proc(a: f32, b: f32, epsilon: f32 = 0.001) -> bool
{
	return abs(a - b) <= epsilon;
}

float_alpha :: proc{
	float_alpha_f32, float_alpha_f64,
}
float_alpha_f32 :: proc(x: f32, min: f32, max: f32, clamp_result: bool = true) -> f32
{
	res := (x - min) / (max - min);
	if clamp_result { res = clamp(res, 0, 1); }
	return res;
}
float_alpha_f64 :: proc(x: f64, min: f64, max: f64, clamp_result: bool = true) -> f64
{
	res := (x - min) / (max - min);
	if clamp_result { res = clamp(res, 0, 1); }
	return res;
}

hex_to_rgba :: u32_to_rgba;
u32_to_rgba :: proc(v: u32) -> Vec4 {
	return Vec4{
		cast(f32)((v & 0xff000000)>>24)/255.0,
		cast(f32)((v & 0x00ff0000)>>16)/255.0,
		cast(f32)((v & 0x0000ff00)>>8) /255.0,
		cast(f32) (v & 0x000000ff)     /255.0,
	};
}

crash :: proc(args: ..any, loc:=#caller_location) {
	log.fatal(..args, location=loc)
}

ms_to_s :: proc(ms: f32) -> f32 {
	return ms / 1000.0
}

rotate_vector :: proc(vec: Vec2, angle: f32) -> Vec2 {
	c := math.cos(math.to_radians(angle))
	s := math.sin(math.to_radians(angle))

	return Vec2{
		vec.x * c - vec.y * s,
		vec.x * s + vec.y * c,
	}
}

angle_from_vector :: proc(v: Vec2) -> f32 {
	return math.to_degrees(math.atan2(v.y, v.x))
}

rand_f32_range :: rand.float32_range
rand_f64_range :: rand.float64_range

// pass in 5, and it'll give a range from 0 -> 5
// max is inclusive
rand_int :: proc(max: int) -> int {
	return int(rand.int31_max(i32(max) + 1))
}

rand_int_range :: proc(min, max: int) -> int {
	spread := max-min
	return rand_int(spread)+min
}

pretty_calendar_time :: proc(t: time.Time) -> string {
	_time_to_string_hms :: proc(t: time.Time, buf: []u8) -> (res: string) #no_bounds_check {
		assert(len(buf) >= time.MIN_HMS_LEN)
		h, m, s := time.clock(t)
	
		buf[7] = '0' + u8(s % 10); s /= 10
		buf[6] = '0' + u8(s)
		buf[5] = '-'
		buf[4] = '0' + u8(m % 10); m /= 10
		buf[3] = '0' + u8(m)
		buf[2] = '-'
		buf[1] = '0' + u8(h % 10); h /= 10
		buf[0] = '0' + u8(h)
	
		return string(buf[:time.MIN_HMS_LEN])
	}

	buf: [time.MIN_YYYY_DATE_LEN]u8
	ymd := time.to_string_yyyy_mm_dd(t, buf[:])
	
	buf2: [time.MIN_HMS_LEN]u8
	clock := _time_to_string_hms(t, buf2[:])
	
	return fmt.tprintf("%v_%v", ymd, clock)
}


// iso8601 format example
// 2023-12-13T15:45:30.123Z or YYYY-MM-DDTHH:MM:SSZ
//
time_to_iso :: proc(t: time.Time) -> string {
	buf: [time.MIN_YYYY_DATE_LEN]u8
	ymd := time.to_string_yyyy_mm_dd(t, buf[:])
	
	buf2: [time.MIN_HMS_LEN]u8
	clock := time.time_to_string_hms(t, buf2[:])
	
	return fmt.tprintf("%vT%vZ", ymd, clock)
}

// init_time will get set on first call
init_time: time.Time;
seconds_since_init :: proc() -> f64 {
	if init_time._nsec == 0 {
		init_time = time.now()
		return 0
	}
	return time.duration_seconds(time.since(init_time))
}

rgb_to_hsv_vec4 :: proc(rgb: Vec4) -> Vec4 {
	r, g, b, a := rgb[0], rgb[1], rgb[2], rgb[3]
	
	max_val := max(r, g, b)
	min_val := min(r, g, b)
	delta := max_val - min_val
	
	// Value (brightness)
	v := max_val
	
	// Saturation
	s: f32 = 0
	if max_val != 0 {
		s = delta / max_val
	}
	
	// Hue
	h: f32 = 0
	if delta != 0 {
		if max_val == r {
			h = 60 * (((g - b) / delta) + (g < b ? 6 : 0))
		} else if max_val == g {
			h = 60 * (((b - r) / delta) + 2)
		} else { // max_val == b
			h = 60 * (((r - g) / delta) + 4)
		}
	}
	
	return Vec4{h, s, v, a}
}

hsv_to_rbg_vec4 :: proc(hsv: Vec4) -> Vec4 {
	h, s, v, a := hsv[0], hsv[1], hsv[2], hsv[3]
	
	// Handle edge cases
	if s == 0 {
		return Vec4{v, v, v, a} // grayscale
	}
	
	h = h / 60.0 // sector 0 to 5
	sector := int(math.floor(h))
	f := h - f32(sector) // factorial part of h
	p := v * (1 - s)
	q := v * (1 - s * f)
	t := v * (1 - s * (1 - f))
	
	r, g, b: f32
	switch sector {
		case 0:
			r, g, b = v, t, p
		case 1:
			r, g, b = q, v, p
		case 2:
			r, g, b = p, v, t
		case 3:
			r, g, b = p, q, v
		case 4:
			r, g, b = t, p, v
		case:
			r, g, b = v, p, q
	}
	
	return Vec4{r, g, b, a}
}

do_highlight :: proc(col: Vec4) -> Vec4 {
	hsv := rgb_to_hsv_vec4(col)
	if hsv.z > 0.8 {
		hsv.z -= 0.2
	} else {
		hsv.z += 0.2
	}
	return hsv_to_rbg_vec4(hsv)
}

swap :: proc(a: ^$T, b: ^T) {
	og := a^
	a^ = b^
	b^ = og
}

quick_n_dirty_string_id :: proc(allocator := context.allocator) -> string {
	// Generate a random alphanumeric string suitable for JSON keys
	chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	length := 12 // Should be long enough to avoid collisions for most purposes

	prefix :: "id_"
	
	result := make([]u8, length, allocator)
	for i in 0..<length {
		idx := rand_int(len(chars) - 1)
		result[i] = chars[idx]
	}
	
	return strings.concatenate({prefix, string(result)}, allocator)
}

// copied this and disabled the crypogrpahic assert, not needed to be that robust lol.
generate_v7_basic_no_crypto :: proc(timestamp: Maybe(time.Time) = nil) -> (result: uuid.Identifier) {
	using uuid
	//assert(.Cryptographic in runtime.random_generator_query_info(context.random_generator), NO_CSPRNG_ERROR)
	unix_time_in_milliseconds := time.to_unix_nanoseconds(timestamp.? or_else time.now()) / 1e6

	result = transmute(Identifier)(cast(u128be)unix_time_in_milliseconds << VERSION_7_TIME_SHIFT)

	bytes_generated := rand.read(result[6:])
	assert(bytes_generated == 10, "RNG failed to generate 10 bytes for UUID v7.")

	result[VERSION_BYTE_INDEX] &= 0x0F
	result[VERSION_BYTE_INDEX] |= 0x70

	result[VARIANT_BYTE_INDEX] &= 0x3F
	result[VARIANT_BYTE_INDEX] |= 0x80

	return
}

is_vec2_fucked :: proc(v: Vec2) -> bool {
	return math.is_nan(v.x) || math.is_nan(v.y) || math.is_inf(v.x) || math.is_inf(v.y)
}

round_to_grid :: proc(v: Vec2, grid_length: f32) -> Vec2 {
	v := v
	v.x = math.round(v.x / grid_length) * grid_length
	v.y = math.round(v.y / grid_length) * grid_length
	return v
}

find_first_match :: proc(array: ^$D/[dynamic]$T, element: T, loc := #caller_location) -> (index:int, found:bool) {
	for e, i in array {
		if e == element {
			index = i
			found = true
			break
		}
	}
	return
}

snap_to_interval :: proc(x: f32, interval: f32) -> f32 {
	return math.round(x / interval) * interval
}
