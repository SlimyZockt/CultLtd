package game

import "core:container/xar"
import "core:fmt"
import rl "vendor:raylib"

import "../steam"

GHOST_COLOR :: rl.Color{0x93, 0x8a, 0xa9, 0xA0}

draw :: proc(ctx: ^GameCtx, delta_time: f32) {
	switch ctx.scene {
	case .Loading:
		default_font := rl.GetFontDefault()
		rl.DrawTextPro(
			default_font,
			"Loading",
			Vec2{ctx.render_size.x / 2, ctx.render_size.y / 2},
			Vec2{},
			0,
			32,
			1,
			rl.DARKGRAY,
		)

	case .Game:
		draw_game(ctx, delta_time)
	case .MainMenu:
		get_ui_pos :: proc(render_size: Vec2, i: f32) -> Vec2 {
			return {(render_size.x / 2) - 100, (render_size.y / 4) + i * 70}
		}

		btn_pos := get_ui_pos(ctx.render_size, 0)
		if rl.GuiButton(rl.Rectangle{btn_pos.x, btn_pos.y, 200, 60}, "Play") {
			ctx.max_player_count = 1
			game_enter(ctx, &g_arena)
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

TILE_SIZE :: 32
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

		rl.DrawTexturePro(
			ctx.world_texture,
			rl.Rectangle{0, 0, WORLD_SIZE, WORLD_SIZE},
			rl.Rectangle{0, 0, WORLD_SIZE * TILE_SIZE, WORLD_SIZE * TILE_SIZE},
			Vec2{},
			0,
			rl.WHITE,
		)

		// rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)

		entity_iter := xar.iterator(&ctx.entities.list)
		for entity, i in xar.iterate_by_ptr(&entity_iter) {
			if .Alive not_in entity.flags do continue
			cstr := fmt.ctprintf("%v:%v", i, entity.generation)
			// log.debug(i, entity.generation)
			rl.DrawTextPro(
				default_font,
				cstr,
				rl.Vector2{entity.position.x, entity.position.y - entity.size.y},
				Vec2{},
				0,
				32,
				1,
				rl.BLACK,
			)
			if entity.texture_id == 0 {
				rl.DrawRectanglePro(
					rl.Rectangle {
						entity.position.x,
						entity.position.y,
						entity.size.x,
						entity.size.y,
					},
					Vec2{},
					0,
					GHOST_COLOR,
				)
			}
		}
	}

	{ 	// draw UI
		rl.DrawRectangle(0, 0, i32(ctx.render_size.x / 2), i32(ctx.render_size.y / 10), rl.GRAY)


		MINIMAP_SIZE :: WORLD_SIZE

		// rl.DrawPixel()
		rl.DrawTexturePro(
			ctx.world_texture,
			rl.Rectangle{0, 0, WORLD_SIZE, WORLD_SIZE},
			rl.Rectangle{ctx.render_size.x - MINIMAP_SIZE, 0, MINIMAP_SIZE, MINIMAP_SIZE},
			Vec2{},
			0,
			rl.WHITE,
		)

		for _, p in ctx.players {
			player_enity, _ := entity_get(&ctx.entities, p.entity)
			rl.DrawRectangle(
				i32(ctx.render_size.x) - (MINIMAP_SIZE) + i32(player_enity.x / TILE_SIZE) - 2,
				i32(player_enity.y / TILE_SIZE) - 2,
				4,
				4,
				rl.BLACK,
			)
		}

	}
}
