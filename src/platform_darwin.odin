package main

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"

_ :: MTL
_ :: CA

Graphics_Backend :: struct {
    app: ^NS.Application,
    wnd: ^NS.Window,

    // Metal-specific objects
    device: ^MTL.Device,
    command_queue: ^MTL.CommandQueue,
    pipeline_state: ^MTL.RenderPipelineState,
    vertex_buffer: ^MTL.Buffer,
    index_buffer: ^MTL.Buffer,
    constant_buffer: ^MTL.Buffer,
    sampler_state: ^MTL.SamplerState,
    layer: ^CA.MetalLayer,
}

_window_open :: proc(title: string) {
    app_state.gfx.backend.app = NS.Application.sharedApplication()
    app_state.gfx.backend.app->setActivationPolicy(.Regular)
    delegate := NS.application_delegate_register_and_alloc({
        applicationShouldTerminateAfterLastWindowClosed = proc(^NS.Application) -> NS.BOOL { return true },
    }, "app_delegate", context)
    app_state.gfx.backend.app->setDelegate(delegate)

    main_screen := NS.Screen_mainScreen()
    screen_rect := main_screen->frame()

    window_width  := NS.Float(800)
    window_height := NS.Float(600)
    center_x := (screen_rect.size.width - window_width) / 2
    center_y := (screen_rect.size.height - window_height) / 2

    app_state.gfx.window_width = int(window_width)
    app_state.gfx.window_height = int(window_height)

    frame_rect := NS.Rect { { center_x, center_y }, { window_width, window_height } }
    app_state.gfx.backend.wnd = NS.Window_alloc()
    app_state.gfx.backend.wnd->initWithContentRect(frame_rect, { .Resizable, .Closable, .Titled }, .Buffered, false)

    window_delegate := NS.window_delegate_register_and_alloc({
        windowShouldClose = proc(window: ^NS.Window) -> bool {
            app_state.running = false
            return true
        },
    }, "window_delegate", context)

    app_state.gfx.backend.wnd->setDelegate(window_delegate)

    title_string :=  NS.String_initWithOdinString(NS.String_alloc(), title)
    app_state.gfx.backend.wnd->setTitle(title_string)
    app_state.gfx.backend.wnd->makeKeyAndOrderFront(nil)
    app_state.gfx.backend.app->activateIgnoringOtherApps(true)
}



_window_show :: proc() {

}

_window_poll :: proc() {
    for {
        event := NS.Application_nextEventMatchingMask(
            app_state.gfx.backend.app,
            NS.EventMaskAny,
            nil,
            NS.DefaultRunLoopMode,
            true
        )

        if event == nil {
            break
        }

        #partial switch NS.Event_type(event) {

            case .MouseMoved, .LeftMouseDragged, .RightMouseDragged, .OtherMouseDragged:
            delta_x := NS.Event_deltaX(event)
            delta_y := NS.Event_deltaY(event)
            app_state.input.mouse_move_delta = {f32(delta_x), f32(delta_y)}

            case .LeftMouseDown:
            update_mouse_state(.Left, true)
            case .LeftMouseUp:
            update_mouse_state(.Left, false)
            case .RightMouseDown:
            update_mouse_state(.Right, true)
            case .RightMouseUp:
            update_mouse_state(.Right, false)
            case .OtherMouseDown:
            if NS.Event_buttonNumber(event) == 2 {
                update_mouse_state(.Middle, true)
            }
            case .OtherMouseUp:
            if NS.Event_buttonNumber(event) == 2 {
                update_mouse_state(.Middle, false)
            }

            case .ScrollWheel:
            app_state.input.mouse_scroll_y = f32(NS.Event_deltaY(event))

            case .KeyDown:
            key := _remap_key(NS.Event_keyCode(event))
            current_state := app_state.input.key_states[key]
            new_pressed_state := current_state.pressed == .None ? Key_State.Pressed : Key_State.Blocked
            app_state.input.key_states[key] = {current = .Pressed, pressed = new_pressed_state}

            case .KeyUp:
            key := _remap_key(NS.Event_keyCode(event))
            app_state.input.key_states[key] = {current = .Released, pressed = .None}

            case:
            // Handle other event types if needed
        }

        NS.Application_sendEvent(app_state.gfx.backend.app, event)
    }

    NS.Application_updateWindows(app_state.gfx.backend.app)
}

update_mouse_state :: proc(button: Mouse_Button, is_down: bool) {
    if is_down {
        current_state := app_state.input.mouse_states[button]
        new_pressed_state := current_state.pressed == .None ? Key_State.Pressed : Key_State.Blocked
        app_state.input.mouse_states[button] = {current = .Pressed, pressed = new_pressed_state}
    } else {
        app_state.input.mouse_states[button] = {current = .Released, pressed = .None}
    }
}

_window_closed :: proc() {
    app_state.running = false
}

_window_on_resized :: proc(width, height: int) {
    app_state.gfx.window_width  = width
    app_state.gfx.window_height = height
    app_state.gfx.window_resized = true
}

_window_show_message_box :: proc(
    title, msg: string,
    msg_type: MessageBoxType,
) {

}

_window_set_title :: proc(title: string) {
}

_window_set_size :: proc(width, height: u32) {
}

_window_get_size :: proc() -> (width, height: int) {
    return app_state.gfx.window_width, app_state.gfx.window_height
}

_window_set_position :: proc(x, y: u32) {
}

_window_set_fullscreen :: proc(fullscreen: bool) {
    if fullscreen != app_state.gfx.fullscreen {
        _graphics_resize_buffers()
    }
}

_graphics_init :: proc() -> () {
    backend := &app_state.gfx.backend

    // Create device
    backend.device = MTL.CreateSystemDefaultDevice()
    assert(backend.device != nil)

    // Create command queue
    backend.command_queue = backend.device->newCommandQueue()
    assert(backend.command_queue != nil)

    // Create swap chain
    backend.layer = CA.MetalLayer.layer()
    backend.layer->setDevice(backend.device)
    backend.layer->setPixelFormat(.BGRA8Unorm_sRGB)
    backend.layer->setFramebufferOnly(true)
    backend.layer->setDrawableSize({NS.Float(app_state.gfx.window_width), NS.Float(app_state.gfx.window_height)})
    backend.wnd->contentView()->setLayer(backend.layer)

    // Create render pipeline state
    library := backend.device->newDefaultLibrary()
    vertex_function := library->newFunctionWithName(NS.AT("vertex_shader"))
    fragment_function := library->newFunctionWithName(NS.AT("fragment_shader"))

    render_pipeline_desc := MTL.RenderPipelineDescriptor.alloc()->init()
    render_pipeline_desc->setVertexFunction(vertex_function)
    render_pipeline_desc->setFragmentFunction(fragment_function)
    render_pipeline_desc->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)

    color_attachment := render_pipeline_desc->colorAttachments()->object(0)
    color_attachment->setBlendingEnabled(true)
    //color_attachment->setSourceRGBBlendFactor(.SourceAlpha)
    color_attachment->setDestinationRGBBlendFactor(.OneMinusSourceAlpha)
    //color_attachment->setRGBBlendOperation(.Add)
    color_attachment->setSourceAlphaBlendFactor(.One)
    color_attachment->setDestinationAlphaBlendFactor(.OneMinusSourceAlpha)
    color_attachment->setAlphaBlendOperation(.Add)

    pipeline_state, pipe_err : = backend.device->newRenderPipelineStateWithDescriptor(render_pipeline_desc)
    assert(backend.pipeline_state != nil && pipe_err == nil)

    backend.pipeline_state = pipeline_state

    // Create vertex buffer
    vertex_buffer_size := NS.UInteger(size_of(Vertex) * MAX_QUADS * 4)
    backend.vertex_buffer = backend.device->newBufferWithLength(vertex_buffer_size, MTL.ResourceStorageModeShared)
    assert(backend.vertex_buffer != nil)

    // Create index buffer
    index_buffer_count :: MAX_QUADS * 6
    indices: [index_buffer_count]u16
    for i := 0; i < index_buffer_count; i += 6 {
        quad_index := u16(i / 6 * 4)
        indices[i + 0] = quad_index + 0
        indices[i + 1] = quad_index + 1
        indices[i + 2] = quad_index + 2
        indices[i + 3] = quad_index + 0
        indices[i + 4] = quad_index + 2
        indices[i + 5] = quad_index + 3
    }
    backend.index_buffer = backend.device->newBufferWithSlice(indices[:], MTL.ResourceStorageModeShared)
    assert(backend.index_buffer != nil)

    // // Create constant buffer
    // constant_buffer_size := size_of(GlobalConstants)
    // backend.constant_buffer = backend.device->newBufferWithLength(constant_buffer_size, MTL.ResourceStorageModeShared)
    // assert(backend.constant_buffer != nil)

    // Create sampler state
    sampler_desc := MTL.SamplerDescriptor.alloc()->init()
    sampler_desc->setMinFilter(.Nearest)
    sampler_desc->setMagFilter(.Nearest)
    sampler_desc->setMipFilter(.Nearest)
    sampler_desc->setSAddressMode(.Repeat)
    sampler_desc->setTAddressMode(.Repeat)
    sampler_desc->setRAddressMode(.Repeat)
    backend.sampler_state = backend.device->newSamplerState(sampler_desc)
    assert(backend.sampler_state != nil)
}

_setup_buffers :: proc() {

}

_graphics_resize_buffers :: proc() {
    if app_state.gfx.window_resized {
        _graphics_resize_buffers()
        app_state.gfx.window_resized = false
    }
}

_graphics_start_frame :: proc() {

}

_graphics_present_frame :: proc() {

}

MacKeyCode ::  u16

_remap_key :: proc(key: MacKeyCode) -> Key_Code {
    switch key {
        // Numeric keys
        case 0x1D: return .Alpha_0
        case 0x12: return .Alpha_1
        case 0x13: return .Alpha_2
        case 0x14: return .Alpha_3
        case 0x15: return .Alpha_4
        case 0x17: return .Alpha_5
        case 0x16: return .Alpha_6
        case 0x1A: return .Alpha_7
        case 0x1C: return .Alpha_8
        case 0x19: return .Alpha_9

        // Function keys
        case 0x7A: return .F1
        case 0x78: return .F2
        case 0x63: return .F3
        case 0x76: return .F4
        case 0x60: return .F5
        case 0x61: return .F6
        case 0x62: return .F7
        case 0x64: return .F8
        case 0x65: return .F9
        case 0x6D: return .F10
        case 0x67: return .F11
        case 0x6F: return .F12

        // Alphabetic keys
        case 0x00: return .A
        case 0x0B: return .B
        case 0x08: return .C
        case 0x02: return .D
        case 0x0E: return .E
        case 0x03: return .F
        case 0x05: return .G
        case 0x04: return .H
        case 0x22: return .I
        case 0x26: return .J
        case 0x28: return .K
        case 0x25: return .L
        case 0x2E: return .M
        case 0x2D: return .N
        case 0x1F: return .O
        case 0x23: return .P
        case 0x0C: return .Q
        case 0x0F: return .R
        case 0x01: return .S
        case 0x11: return .T
        case 0x20: return .U
        case 0x09: return .V
        case 0x0D: return .W
        case 0x07: return .X
        case 0x10: return .Y
        case 0x06: return .Z

        // Arrow keys
        case 0x7E: return .Up
        case 0x7D: return .Down
        case 0x7B: return .Left
        case 0x7C: return .Right

        // Navigation keys
        case 0x72: return .Insert  // There's no Insert key on Mac, using Help key
        case 0x75: return .Delete
        case 0x73: return .Home
        case 0x77: return .End
        case 0x74: return .Page_Up
        case 0x79: return .Page_Down

        // Symbol keys
        case 0x32: return .Back_Quote
        case 0x2B: return .Comma
        case 0x2F: return .Period
        case 0x2C: return .Forward_Slash
        case 0x2A: return .Back_Slash
        case 0x29: return .Semicolon
        case 0x27: return .Apostrophe
        case 0x21: return .Left_Bracket
        case 0x1E: return .Right_Bracket
        case 0x1B: return .Minus
        case 0x18: return .Equals

        // Modifier keys
        case 0x3B: return .Control_Left
        case 0x3E: return .Control_Right
        case 0x3A: return .Alt_Left
        case 0x3D: return .Alt_Right
        case 0x37: return .Super_Left
        case 0x36: return .Super_Right

        // Special keys
        case 0x30: return .Tab
        case 0x39: return .Capslock
        case 0x38: return .Shift_Left
        case 0x3C: return .Shift_Right
        case 0x24: return .Enter
        case 0x31: return .Space
        case 0x33: return .Backspace
        case 0x35: return .Escape

        // Numpad keys
        case 0x52: return .Num_0
        case 0x53: return .Num_1
        case 0x54: return .Num_2
        case 0x55: return .Num_3
        case 0x56: return .Num_4
        case 0x57: return .Num_5
        case 0x58: return .Num_6
        case 0x59: return .Num_7
        case 0x5B: return .Num_8
        case 0x5C: return .Num_9
        case 0x45: return .Num_Add
        case 0x4E: return .Num_Subtract
        case 0x43: return .Num_Multiply
        case 0x4B: return .Num_Divide
        case 0x41: return .Num_Decimal

        case: return .INVALID  // Default case for unmapped keys
    }
}