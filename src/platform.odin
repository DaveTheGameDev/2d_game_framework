package main

import "core:prof/spall"
import "core:time"
import "core:math"
import "core:math/linalg"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:log"
import "base:runtime"

import stbi  "vendor:stb/image"

PROFILE_ENABLE :: #config(PROFILE_ENABLE, false)

MAX_QUADS :: 8192
Quad      :: distinct [4]Vertex

Vertex :: struct #align(16) {
    pos:          Vec2,
    col:          Color,
    uv:           Vec2,
    col_override: Color,
    tex_index:      u8,
}

app_state: App_State

App_State :: struct {
    input: Input_State,
    gfx:   Graphics_State,
    odin_ctx: runtime.Context,
    running: bool,
}

Input_State :: struct {
    mouse_scroll_y:   [2]f32,
    mouse_move_delta: [2]f32,
    mouse_position:   [2]int,
    key_states:       [Key_Code]Key_State_Pair,
    mouse_states:     [Mouse_Button]Key_State_Pair,
}

Camera :: struct {
    pos:  Vec2,
    zoom: f32,
    res:  Vec2
}

Graphics_State :: struct {
    backend: Graphics_Backend,

    fullscreen:    bool,
    screen_height: int,
    screen_width:  int,
    window_height: int,
    window_width:  int,

    window_focused: bool,
    window_resized: bool,

    frame: struct {
        quads:        [MAX_QUADS]Quad,
        clear_color:  Color,
        quad_count:   int,
        projection:   Mat4,
        camera_xform: Mat4,
        camera:       Camera,
        draw_origin:  Origin,
    }
}

Pivot :: enum {
    center,
    center_right,
    center_left,
    top_center,
    top_left,
    top_right,

    bottom_center,
    bottom_left,
    bottom_right,
}

Origin :: enum {
    Center,
    Bottom_Left,
}


MessageBoxType :: enum {
    Info,
    Warning,
    Error,
}


ShaderType :: enum {
    Vertex,
    Pixel,
    Geometry,
    Hull,
    Domain,
    Compute,
    Mesh,
}


// HELPERS
ctstr :: fmt.ctprintf
tstr  :: fmt.tprint
tstrf :: fmt.tprintf

cstr_clone :: proc(text: string, allocator := context.allocator) -> cstring {
    return strings.clone_to_cstring(text, allocator)
}

// LOGGING
log_info  :: log.infof
log_warn  :: log.warnf
log_error :: log.errorf
printf    :: fmt.printfln

// MATH
Vec2  :: [2]f32
Vec3  :: [3]f32
Vec4  :: [4]f32
Mat4  :: linalg.Matrix4f32
Ortho :: linalg.matrix_ortho3d_f32

DEFAULT_UV :: Vec4{0, 0, 1, 1}

xform_translate :: proc(pos: Vec2) -> Mat4 {
    return linalg.matrix4_translate_f32({pos.x, pos.y, 0})
}

xform_rotate :: proc(angle: f32) -> Mat4 {
    return linalg.matrix4_rotate_f32(math.to_radians(angle), {0, 0, 1})
}

xform_scale :: proc(scale: Vec2) -> Mat4 {
    return linalg.matrix4_scale_f32(Vec3{scale.x, scale.y, 1})
}

scale_from_pivot :: proc(pivot: Pivot) -> Vec2 {
	switch pivot {
		case .bottom_left:   return {0.0, 0.0}
		case .bottom_center: return {0.5, 0.0}
		case .bottom_right:  return {1.0, 0.0}
		case .center_left:   return {0.0, 0.5}
		case .center:        return {0.5, 0.5}
		case .center_right:  return {1.0, 0.5}
		case .top_center:    return {0.5, 1.0}
		case .top_left:      return {0.0, 1.0}
		case .top_right:     return {1.0, 1.0}
		case: return 0
	}
}


// COLOR
Color :: [4]f32

rgb :: proc(r, g, b: u8, a: u8= 255) -> Color {
    return Color{
        f32(r) / 255.0,
        f32(g) / 255.0,
        f32(b) / 255.0,
        f32(a) / 255.0,
    }
}

hex :: proc(hex: u32, alpha: u8 = 255) -> Color {
    r, g, b, a: u8
    if hex <= 0xFFFFFF { // RGB only
        r = u8((hex >> 16) & 0xFF)
        g = u8((hex >> 8) & 0xFF)
        b = u8(hex & 0xFF)
        return rgb(r, g, b, alpha)
    } else { // RGBA
        r = u8((hex >> 24) & 0xFF)
        g = u8((hex >> 16) & 0xFF)
        b = u8((hex >> 8) & 0xFF)
        a = u8(hex & 0xFF)
        return rgb(r, g, b, a)
    }
}

COLOR_RED     :: Color { 1,   0,   0,   1 }
COLOR_WHITE   :: Color { 1,   1,   1,   1 }
COLOR_GREEN   :: Color { 0,   1,   0,   1 }
COLOR_BLUE    :: Color { 0,   0,   1,   1 }
COLOR_YELLOW  :: Color { 1,   1,   0,   1 }
COLOR_CYAN    :: Color { 0,   1,   1,   1 }
COLOR_MAGENTA :: Color { 1,   0,   1,   1 }
COLOR_ORANGE  :: Color { 1,   0.5, 0,   1 }
COLOR_PURPLE  :: Color { 0.5, 0,   0.5, 1 }
COLOR_BROWN   :: Color { 0.6, 0.4, 0.2, 1 }
COLOR_GRAY    :: Color { 0.5, 0.5, 0.5, 1 }
COLOR_BLACK   :: Color { 0,   0,   0,   1 }
COLOR_ZERO    :: Color { 0,   0,   0,   0 }


// APP
main :: proc() {
    when PROFILE_ENABLE {
        spall_ctx = spall.context_create("trace.spall", 1)
        defer spall.context_destroy(&spall_ctx)
        spall_buffer_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)
        spall_buffer = spall.buffer_create(spall_buffer_backing, 0)
        defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
    }

    mode: int = 0
    when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
    }
    logh, logh_err := os.open("log.txt", (os.O_CREATE | os.O_TRUNC | os.O_RDWR), mode)

    when !ODIN_DEBUG {
        if logh_err == os.ERROR_NONE {
            os.stdout = logh
            os.stderr = logh
        }
    }

    LOG_OPTIONS :: log.Options{
    	.Level,
    	//.Terminal_Color,
    	//.Short_File_Path,
    	//.Line,
    	.Procedure,
    }

    logger := logh_err == os.ERROR_NONE ? log.create_multi_logger(log.create_file_logger(logh, opt=LOG_OPTIONS), log.create_console_logger(opt=LOG_OPTIONS)) : log.create_console_logger(opt=LOG_OPTIONS)
    context.logger = logger
    app_state.odin_ctx = context

    window_open(GAME_TITLE)

    data, width, height, ok := load_image("res/img/atlas.png")
    ensure(ok, "Failed to load new texture atlas")

    app_state.gfx.backend.main_texture, ok  = _upload_texture(&data[0], width, height)
    ensure(ok, "Failed to upload texture atlas")

    game_init()

    last_frame_time := time.now()
    for app_state.running {
        dt := f32(time.duration_seconds(time.since(last_frame_time)))
        dt = math.clamp(dt, 0.0, 1.0)
        last_frame_time = time.now()

        gameplay_update_scope: {
            PROFILE("Game Update")
            game_update(dt)
        }

        gameplay_draw_scope: {
            PROFILE("Game Draw")
            game_draw(dt)
        }

        frame_start()

        frame_end()
        app_state.gfx.frame = {}
    }
}

frame_start :: proc() {
    PROFILE(#procedure)
    window_poll()
    graphics_start_frame()
}

frame_end :: proc() {
    PROFILE(#procedure)
    graphics_present_frame()
    reset_input_state()
    free_all(context.temp_allocator)
}

quit :: proc() {
    app_state.running = false
}

when PROFILE_ENABLE {
    spall_ctx: spall.Context
    spall_buffer_backing: []u8
    spall_buffer: spall.Buffer
}

@(deferred_in=_profile_buffer_end)
@(disabled=!PROFILE_ENABLE)
PROFILE :: proc(name: string, args: string = "", location := #caller_location) {
    spall._buffer_begin(&spall_ctx, &spall_buffer, name, args, location)
}

@(private)
@(disabled=!PROFILE_ENABLE)
_profile_buffer_end :: proc(_, _: string, _ := #caller_location) {
	spall._buffer_end(&spall_ctx, &spall_buffer)
}

// WINDOWING
window_open :: proc(title: string) {
    app_state.gfx.frame.clear_color = 1
    _window_open(title)
    _graphics_init()
    app_state.running = true
}

window_poll :: proc() {
    PROFILE(#procedure)
    _window_poll()
}

window_show_message_box :: proc(title, msg: string, msg_type: MessageBoxType) {
    _window_show_message_box(title, msg, msg_type)
}

window_show :: proc() {
    _window_show()
}

window_set_fullscreen :: proc(fullscreen: bool) {
    _window_set_fullscreen(fullscreen)
}

// GRAPHICS
graphics_start_frame :: proc() {
    PROFILE(#procedure)
    _graphics_start_frame()
}

graphics_present_frame :: proc() {
    PROFILE(#procedure)
    _graphics_present_frame()
}

set_camera :: proc(pos: Vec2, zoom: f32, res := Vec2{}, origin: Origin = .Center) {
    app_state.gfx.frame.camera.pos = pos
    render_res := res

    if render_res == {} {
        render_res = {f32(app_state.gfx.window_width), f32(app_state.gfx.window_height)}
    }

    window_aspect := f32(app_state.gfx.window_width) / f32(app_state.gfx.window_height)
    camera_aspect := render_res.x / render_res.y

    width, height: f32
    if window_aspect > camera_aspect {
        height = render_res.y / zoom
        width = height * window_aspect
    } else {
        width = render_res.x / zoom
        height = width / window_aspect
    }

    switch origin {
    case .Center:
        app_state.gfx.frame.projection = Ortho(-width * 0.5, width * 0.5, -height * 0.5, height * 0.5, -1, 1)
    case .Bottom_Left:
        app_state.gfx.frame.projection = Ortho(0, width, 0, height, -1, 1)
    }

    app_state.gfx.frame.camera_xform = 1
    app_state.gfx.frame.camera_xform *= xform_translate(pos)
    app_state.gfx.frame.camera_xform *= xform_scale(Vec2{1, 1}) // Remove zoom from here
}

draw_sprite :: proc(pos: Vec2, img_id: Image_Name, pivot:= Pivot.bottom_center, color:=COLOR_WHITE, color_override:=COLOR_ZERO) {
	image := IMAGE_INFO[img_id]
	size := Vec2{f32(image.width), f32(image.height)}

	xform0 := Mat4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform_translate(size * -scale_from_pivot(pivot))

	draw_rect_matrix(xform0, size, color=color, color_override=color_override, img_id=img_id, uv=image.uv)
}

draw_sprite_in_rect :: proc(rect: Rect, img_id: Image_Name, pivot := Pivot.center, color := COLOR_WHITE, color_override := COLOR_ZERO) {
    image := IMAGE_INFO[img_id]
    img_size := Vec2{auto_cast image.width, auto_cast image.height}
    rect_size := Vec2{rect.width, rect.height}

    // Calculate scale to fit the image within the rect while maintaining aspect ratio
    scale := min(rect_size.x / img_size.x, rect_size.y / img_size.y)
    scaled_size := img_size * scale

    // Calculate position to center the scaled image within the rect
    pos := Vec2{rect.x, rect.y} + (rect_size - scaled_size) * 0.5

    // Create transformation matrix
    xform := Mat4(1)
    xform *= xform_translate({pos.x, pos.y})
    xform *= xform_scale(scale)
    xform *= xform_translate(img_size * -scale_from_pivot(pivot))

    draw_rect_matrix(xform, img_size, color=color, color_override=color_override, img_id=img_id, uv=image.uv)
}


draw_rect :: proc(rect: Rect, pivot: Pivot, color: Color, color_override:=COLOR_ZERO, uv:=DEFAULT_UV,  img_id: Image_Name= .nil) {
    PROFILE(#procedure)
    xform := linalg.matrix4_translate(Vec3{rect.x, rect.y, 0})
	xform *= xform_translate({rect.width, rect.height} * -scale_from_pivot(pivot))
	draw_rect_matrix(xform, {rect.width, rect.height}, color, color_override, uv, img_id)
}

draw_rect_matrix :: proc(xform: Mat4, size: Vec2, color: Color, color_override:=COLOR_ZERO, uv:=DEFAULT_UV, img_id: Image_Name= .nil) {
    draw_rect_projected(app_state.gfx.frame.projection * linalg.inverse(app_state.gfx.frame.camera_xform) * xform, size, color, color_override, uv, img_id)
}

draw_rect_projected :: proc(
    world_to_clip: Mat4,
    size:          Vec2,

    col            := COLOR_WHITE,
    color_override := COLOR_ZERO,
    uv             := DEFAULT_UV,
    img_id         := Image_Name.nil,
) {
    PROFILE(#procedure)
    bl := Vec2{ 0, 0 }
	tl := Vec2{ 0, size.y }
	tr := Vec2{ size.x, size.y }
	br := Vec2{ size.x, 0 }

    uv0 := uv
    if uv == DEFAULT_UV {
        //tex := app_state.gfx.backend.main_texture
        uv0 = {0,0, 1, 1}
    }

    tex_index :[4]u8= 0 //atlas_image.tex_index

	if img_id == .nil {
		tex_index = 255 // bypasses texture sampling
		//log_info("Not using a texture")
	}

	if img_id == .font {
		tex_index = 1 // draws the font
	}

	draw_quad_projected(world_to_clip, {bl, tl, tr, br}, col, {uv0.xy, uv0.xw, uv0.zw, uv0.zy}, tex_index, color_override)
}

draw_quad_projected :: proc(
	world_to_clip:   Mat4,
	positions:       [4]Vec2,
	colors:          [4]Color,
	uvs:             [4]Vec2,
    tex_indicies:    [4]u8,
    col_overrides:   [4]Color,
) {
	if app_state.gfx.frame.quad_count >= MAX_QUADS {
		log_error("max quads reached")
		return
	}
    PROFILE(#procedure)
	verts := &app_state.gfx.frame.quads[app_state.gfx.frame.quad_count]
	app_state.gfx.frame.quad_count += 1

	verts[0].pos = (world_to_clip * Vec4{positions[0].x, positions[0].y, 0.0, 1.0}).xy
	verts[1].pos = (world_to_clip * Vec4{positions[1].x, positions[1].y, 0.0, 1.0}).xy
	verts[2].pos = (world_to_clip * Vec4{positions[2].x, positions[2].y, 0.0, 1.0}).xy
	verts[3].pos = (world_to_clip * Vec4{positions[3].x, positions[3].y, 0.0, 1.0}).xy

	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

    verts[0].uv = uvs[0]
    verts[1].uv = uvs[1]
    verts[2].uv = uvs[2]
    verts[3].uv = uvs[3]


    verts[0].tex_index = tex_indicies[0]
    verts[1].tex_index = tex_indicies[1]
    verts[2].tex_index = tex_indicies[2]
    verts[3].tex_index = tex_indicies[3]

    verts[0].col_override = col_overrides[0]
    verts[1].col_override = col_overrides[1]
    verts[2].col_override = col_overrides[2]
    verts[3].col_override = col_overrides[3]
}

//INUPT
key_pressed_mod :: proc(mod, key: Key_Code) -> bool {
    return #force_inline key_down(mod) && #force_inline key_pressed(key)
}

key_pressed :: proc(key: Key_Code) -> bool {
    return app_state.input.key_states[key].pressed == .Pressed
}

key_released :: proc(key: Key_Code) -> bool {
    return app_state.input.key_states[key].current == .Released
}

key_down :: proc(key: Key_Code) -> bool {
    return app_state.input.key_states[key].current == .Pressed
}

mouse_pressed :: proc(btn: Mouse_Button) -> bool {
    return app_state.input.mouse_states[btn].pressed == .Pressed
}

mouse_released :: proc(btn: Mouse_Button) -> bool {
    return app_state.input.mouse_states[btn].current == .Released
}

mouse_down :: proc(btn: Mouse_Button) -> bool {
    return app_state.input.mouse_states[btn].current == .Pressed
}

mouse_position_screen_int :: proc() -> [2]int {
    return app_state.input.mouse_position
}

mouse_position_screen :: proc() -> [2]f32 {
    return {f32(app_state.input.mouse_position.x), f32(app_state.input.mouse_position.y)}
}

reset_input_state :: proc() {
    app_state.input.mouse_scroll_y = 0

    for key in Key_Code {
        if app_state.input.key_states[key].current == .Released {
            app_state.input.key_states[key].current = .None
        }
        if app_state.input.key_states[key].pressed == .Pressed {
            app_state.input.key_states[key].pressed = .Blocked
        }
    }

    for btn in Mouse_Button {
        if app_state.input.mouse_states[btn].current == .Released {
            app_state.input.mouse_states[btn].current = .None
        }
        if app_state.input.mouse_states[btn].pressed == .Pressed {
            app_state.input.mouse_states[btn].pressed = .Blocked
        }
    }
}


Key_State :: enum {
    None,
    Pressed,
    Released,
    Blocked,
}

Key_State_Pair :: struct {
    current: Key_State,
    pressed: Key_State,
}

Mouse_Button :: enum {
    Left,
    Middle,
    Right,
}

Key_Code :: enum {
    // Numeric keys
    Alpha_0,
    Alpha_1,
    Alpha_2,
    Alpha_3,
    Alpha_4,
    Alpha_5,
    Alpha_6,
    Alpha_7,
    Alpha_8,
    Alpha_9,

    // Function keys
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,

    // Alphabetic keys
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,

    // Arrow keys
    Up,
    Down,
    Left,
    Right,

    // Navigation keys
    Insert,
    Delete,
    Home,
    End,
    Page_Up,
    Page_Down,

    // Symbol keys
    Back_Quote,
    Comma,
    Period,
    Forward_Slash,
    Back_Slash,
    Semicolon,
    Apostrophe,
    Left_Bracket,
    Right_Bracket,
    Minus,
    Equals,

    // Modifier keys
    Control_Left,
    Control_Right,
    Alt_Left,
    Alt_Right,
    Super_Left,
    Super_Right,

    // Special keys
    Tab,
    Capslock,
    Shift_Left,
    Shift_Right,
    Enter,
    Space,
    Backspace,
    Escape,

    // Numpad keys
    Num_0,
    Num_1,
    Num_2,
    Num_3,
    Num_4,
    Num_5,
    Num_6,
    Num_7,
    Num_8,
    Num_9,
    Num_Equal,
    Num_Decimal,
    Num_Enter,
    Num_Add,
    Num_Subtract,
    Num_Multiply,
    Num_Divide,

    INVALID,
}


// Fancy Types
Rect :: struct {
	x: f32,
	y: f32,
	width: f32,
	height: f32,
}

// We do Y up
cut_rect_bottom :: proc(r: ^Rect, y: f32, m: f32) -> Rect {
	res := r^
	res.y += m
	res.height = y
	r.y += y + m
	r.height -= y + m
	return res
}

cut_rect_top :: proc(r: ^Rect, h: f32, m: f32) -> Rect {
	res := r^
	res.height = h
	res.y = r.y + r.height - h - m
	r.height -= h + m
	return res
}

cut_rect_left :: proc(r: ^Rect, x, m: f32) -> Rect {
	res := r^
	res.x += m
	res.width = x
	r.x += x + m
	r.width -= x + m
	return res
}

cut_rect_right :: proc(r: ^Rect, w, m: f32) -> Rect {
	res := r^
	res.width = w
	res.x = r.x + r.width - w - m
	r.width -= w + m
	return res
}

split_rect_top :: proc(r: Rect, y: f32, m: f32) -> (top, bottom: Rect) {
	top = r
	bottom = r
	top.y += m
	top.height = y
	bottom.y += y + m
	bottom.height -= y + m
	return
}

split_rect_left :: proc(r: Rect, x: f32, m: f32) -> (left, right: Rect) {
	left = r
	right = r
	left.width = x
	right.x += x + m
	right.width -= x +m
	return
}

split_rect_bottom :: proc(r: Rect, y: f32, m: f32) -> (top, bottom: Rect) {
	top = r
	top.height -= y + m
	bottom = r
	bottom.y = top.y + top.height + m
	bottom.height = y
	return
}

split_rect_right :: proc(r: Rect, x: f32, m: f32) -> (left, right: Rect) {
	left = r
	right = r
	right.width = x
	left.width -= x + m
	right.x = left.x + left.width
	return
}

inset_rect :: proc(r: ^Rect, inset_x: f32, inset_y: f32) -> Rect {
    res := r^
    res.x += inset_x
    res.y += inset_y
    res.width -= 2 * inset_x
    res.height -= 2 * inset_y
    return res
}

make_rect :: proc(pos, size: Vec2) -> Rect {
    return {pos.x, pos.y, size.x, size.y}
}

load_image :: proc(path: string) -> (data: [^]byte, width, height: int, ok: bool) {
    png_data, succ := os.read_entire_file(path)
    if !succ {
        fmt.eprintln("Failed to read image file:", path)
        return
    }

    w, h, channels: i32
    img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &w, &h, &channels, 4)
    if img_data == nil {
        fmt.eprintln("stbi load failed, invalid image?")
        return
    }

    log_info("Loaded image from path: {} ({}x{})", path, w, h)

    return img_data,  int(w), int(h), true
}
