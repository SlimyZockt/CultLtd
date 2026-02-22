package game

import "core:container/xar"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

import "../steam"

draw :: proc(ctx: ^CultCtx, delta_time: f32) {
	switch ctx.scene {
	case .Loading:
		default_font := rl.GetFontDefault()
		rl.DrawTextPro(
			default_font,
			"Loading",
			[2]f32{ctx.render_size.x / 2, ctx.render_size.y / 2},
			[2]f32{},
			0,
			32,
			1,
			rl.DARKGRAY,
		)

	case .Game:
		draw_game(ctx, delta_time)
	case .MainMenu:
		get_ui_pos :: proc(render_size: [2]f32, i: f32) -> [2]f32 {
			return {(render_size.x / 2) - 100, (render_size.y / 4) + i * 70}
		}

		btn_pos := get_ui_pos(ctx.render_size, 0)
		if rl.GuiButton(rl.Rectangle{btn_pos.x, btn_pos.y, 200, 60}, "Play") {
			ctx.max_player_count = 1
			allocator := vmem.arena_allocator(&g_arena)
			game_enter(ctx, allocator)
		}

		when PLATFORM == .STEAM {
			btn_pos = get_ui_pos(ctx.render_size, 1)
			if rl.GuiButton(rl.Rectangle{btn_pos.x, btn_pos.y, 200, 60}, "Host") {
				steam.create_lobby(&ctx.steam)
			}
		}
	}

	if .DebugCross in ctx.flags {
		rl.DrawLine(
			0,
			i32(ctx.render_size.y) / 2,
			i32(ctx.render_size.x),
			i32(ctx.render_size.y) / 2,
			rl.DARKGRAY,
		)

		rl.DrawLine(
			i32(ctx.render_size.x) / 2,
			0,
			i32(ctx.render_size.x) / 2,
			i32(ctx.render_size.y),
			rl.DARKGRAY,
		)
	}

}

draw_game :: proc(ctx: ^CultCtx, delta_time: f32) {
	player, ok := ctx.players[ctx.player_id]
	if ok {
		entity, _ := entity_get(&ctx.entities, player.entity)
		if entity != nil && .Alive in entity.flags {
			ctx.camera.target = entity.position + (entity.size / 2)
		}
	}

	{ 	// Render world
		rl.BeginMode2D(ctx.camera)
		defer rl.EndMode2D()
		default_font := rl.GetFontDefault()

		rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)

		entity_iter := xar.iterator(&ctx.entities.list)
		for entity in xar.iterate_by_ptr(&entity_iter) {
			i := u64(entity_iter.idx) - 1
			if .Alive not_in entity.flags do continue
			cstr := fmt.ctprintf("%v:%v", i, entity.generation)
			// log.debug(i, entity.generation)
			rl.DrawTextPro(
				default_font,
				cstr,
				[2]f32{entity.position.x, entity.position.y - entity.size.y},
				[2]f32{},
				0,
				32,
				1,
				rl.BLACK,
			)
			rl.DrawRectanglePro(
				rl.Rectangle{entity.position.x, entity.position.y, entity.size.x, entity.size.y},
				[2]f32{},
				0,
				rl.Color{0xFF, 0x0, 0x0, 0xA0},
			)
		}
	}


	{ 	// draw UI
		rl.DrawRectangle(0, 0, i32(ctx.render_size.x / 2), i32(ctx.render_size.y / 10), rl.GRAY)
	}
}
