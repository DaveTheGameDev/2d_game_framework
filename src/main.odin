package main

import "core:math/linalg"
import "core:math"

GAME_TITLE :: "test"

Entity :: struct {
    max_speed:    f32,
    acceleration: f32,
    position:     vec2,
    velocity:     vec2,
}

player: Entity

game_init :: proc() {
    app_state.gfx.frame.clear_color = {0, 0.47, 0.84, 1}
    when !ODIN_DEBUG {
        window_set_fullscreen(true)
    }

    player.max_speed = 0.5
    player.acceleration = 12
}

game_update :: proc(dt: f32) {
     set_camera({0, 0}, 1, {640, 380}, .Center)
     if key_pressed(.Escape) {
        quit()
    }

    if key_pressed(.F11) {
        window_set_fullscreen(!app_state.gfx.fullscreen)
    }

    input_dir: vec2

    if key_down(.W) {
        input_dir.y += 1
    }

    if key_down(.A) {
        input_dir.x -= 1
    }

    if key_down(.S) {
         input_dir.y -= 1
    }

    if key_down(.D) {
         input_dir.x += 1
    }

    if linalg.length(input_dir) > 0 {
        input_dir = linalg.normalize(input_dir)
        player.velocity += input_dir * player.acceleration * dt
    } else {
        deceleration_rate :f32= 50.0 // Adjust this value to control deceleration speed
        player.velocity *= math.pow(f32(0.5), deceleration_rate * dt)
    }

    if linalg.length(player.velocity) > player.max_speed {
        player.velocity = linalg.normalize(player.velocity) * player.max_speed
    }

    player.position += player.velocity
}

game_draw :: proc(dt: f32) {
     app_state.gfx.frame.clear_color = {0, 0.47, 0.84, 1}
     draw_sprite( player.position, .entity_chicken, .center, 1)
}

game_imgui_frame :: proc(dt: f32) {

}

game_shutdown :: proc() {

}