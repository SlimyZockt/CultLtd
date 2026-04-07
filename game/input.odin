package game

import "../steam"
import "core:math/linalg"
import rl "vendor:raylib"

is_input_down :: proc(keymap: [Action]Inputs, action: Action) -> bool {
	switch k in keymap[action] {
	case rl.KeyboardKey:
		return rl.IsKeyDown(k)
	case rl.MouseButton:
		return rl.IsMouseButtonDown(k)
	}

	unreachable()
}

is_input_pressed :: proc(keymap: [Action]Inputs, action: Action) -> bool {
	switch k in keymap[action] {
	case rl.KeyboardKey:
		return rl.IsKeyPressed(k)
	case rl.MouseButton:
		return rl.IsMouseButtonPressed(k)
	}

	unreachable()
}

// get_screen_pos_to_game_pos :: proc(mouse_pos: Vec2) -> (virual_mouse_pos: Vec2) {
// 	// player.mouse_screen_position = rl.GetMousePosition()
// 	virtual_position.x =
// 		(player.mouse_screen_position.x - ctx.render_rect.x) / g_game_ctx.render_scale
// 	player.mouse_virtual_screen_position.y =
// 		(player.mouse_screen_position.y - ctx.render_rect.y) / g_game_ctx.render_scale
// 	player.mouse_virtual_screen_position = linalg.clamp(
// 		player.mouse_virtual_screen_position,
// 		0,
// 		Vec2{RENDER_WIDTH, RENDER_HEIGHT},
// 	)
//
// 	return
// }

update_input :: proc(ctx: ^GameCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	player := ctx.players[ctx.player_id]
	input_down := &player.input_down
	input_pressed := &player.input_pressed

	for action in Action {
		input_down^ =
			input_down^ + {action} if is_input_down(ctx.keymap, action) else input_down^ - {action}
		if is_input_pressed(ctx.keymap, action) {
			// input_pressed[i] = ACTIONS_PRESSED_BUFFER_TIME
			input_pressed^ += {action}
		}
	}

	player.mouse_screen_position = rl.GetMousePosition()
	player.mouse_virtual_screen_position.x =
		(player.mouse_screen_position.x - ctx.render_rect.x) / g_game_ctx.render_scale
	player.mouse_virtual_screen_position.y =
		(player.mouse_screen_position.y - ctx.render_rect.y) / g_game_ctx.render_scale
	player.mouse_virtual_screen_position = linalg.clamp(
		player.mouse_virtual_screen_position,
		0,
		Vec2{RENDER_WIDTH, RENDER_HEIGHT},
	)
	player.mouse_position_world = rl.GetScreenToWorld2D(
		player.mouse_virtual_screen_position,
		ctx.camera,
	)

	ctx.players[ctx.player_id] = player

	if is_input_pressed(ctx.keymap, .DebugCross) {
		if .DebugCross in ctx.flags {
			ctx.flags -= {.DebugCross}
		} else {
			ctx.flags += {.DebugCross}
		}
	}

	if is_input_pressed(ctx.keymap, .Quit) {
		game_exit(ctx)
		steam.disconnect(&ctx.steam)
	}
	// input_pressed^ =
	// 	input_pressed^ + {i} if is_input_pressed(ctx.keymap, i) else input_pressed^ - {i}

}
