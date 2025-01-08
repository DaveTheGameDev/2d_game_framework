package main

import NS  "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA  "vendor:darwin/QuartzCore"

_ :: MTL
_ :: CA

Graphics_Backend :: struct {
    app: ^NS.Application,
	wnd: ^NS.Window,
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

        NS.Application_sendEvent(app_state.gfx.backend.app, event)
    }

    NS.Application_updateWindows(app_state.gfx.backend.app)
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
    _window_show()
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