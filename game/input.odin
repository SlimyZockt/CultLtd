package game

import "../steam"
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

update_input :: proc(ctx: ^CultCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	player := ctx.players[ctx.player_id]
	input_down := &player.input_down
	input_pressed := &player.input_pressed

	for i in 0 ..< len(Action) {
		i := Action(i)
		input_down^ = input_down^ + {i} if is_input_down(ctx.keymap, i) else input_down^ - {i}
		if is_input_pressed(ctx.keymap, i) {
			// input_pressed[i] = ACTIONS_PRESSED_BUFFER_TIME
			input_pressed^ += {i}
		}
	}

	player.mouse_position_screen = rl.GetMousePosition()
	player.mouse_position_world = rl.GetScreenToWorld2D(player.mouse_position_screen, ctx.camera)

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
