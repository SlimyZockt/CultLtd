package game

import "core:container/xar"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

import "../steam"

draw :: proc(ctx: ^GameCtx, delta_time: f32) {
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

draw_game :: proc(ctx: ^GameCtx, delta_time: f32) {
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


		for chunk_x in 0 ..< CHUNK_SIZE {
			for chunk_y in 0 ..< CHUNK_SIZE {
				i := chunk_x + (chunk_y * CHUNK_SIZE)

				chunk_pos := ctx.chunked_world[i].pos * TILE_SIZE
				switch ctx.chunked_world[i].biome {
				case .OCEAN:
					rl.DrawRectangle(
						i32(chunk_pos.x),
						i32(chunk_pos.y),
						TILE_SIZE,
						TILE_SIZE,
						rl.BLUE,
					)
				case .PLAINS:
					rl.DrawRectangle(
						i32(chunk_pos.x),
						i32(chunk_pos.y),
						TILE_SIZE,
						TILE_SIZE,
						rl.GREEN,
					)
				case .SNOW:
					rl.DrawRectangle(
						i32(chunk_pos.x),
						i32(chunk_pos.y),
						TILE_SIZE,
						TILE_SIZE,
						rl.LIGHTGRAY,
					)
				case .DESSERT, .FORREST, .SPECIAL:
				}
			}
		}

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
			if entity.texture_id == 0 {
				GHOST_COLOR :: rl.Color{0x93, 0x8a, 0xa9, 0xA0}
				rl.DrawRectanglePro(
					rl.Rectangle {
						entity.position.x,
						entity.position.y,
						entity.size.x,
						entity.size.y,
					},
					[2]f32{},
					0,
					GHOST_COLOR,
				)
			}
		}
	}

	{ 	// draw UI
		rl.DrawRectangle(0, 0, i32(ctx.render_size.x / 2), i32(ctx.render_size.y / 10), rl.GRAY)
	}
}
