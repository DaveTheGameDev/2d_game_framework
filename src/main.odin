package main

GAME_TITLE :: "test"

game_init :: proc() {
    app_state.gfx.frame.clear_color = {0, 0.47, 0.84, 1}
    when !ODIN_DEBUG {
        window_set_fullscreen(true)
    }
}

game_update :: proc(dt: f32) {
    set_camera({0, 0}, 1.1, {640, 380})
     if key_pressed(.Escape) {
        quit()
        
    }

    if key_pressed(.F11) {
        window_set_fullscreen(!app_state.gfx.fullscreen)
    }
}

game_draw :: proc(dt: f32) {
     app_state.gfx.frame.clear_color = {0, 0.47, 0.84, 1}
     draw_sprite({0,0}, .base, .center, 1)

}

game_imgui_frame :: proc(dt: f32) {

}

game_shutdown :: proc() {

}