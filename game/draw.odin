package game

import "core:container/xar"
import "core:fmt"
import "core:log"
import "core:math/linalg"
import rl "vendor:raylib"

import "../steam"

GHOST_COLOR :: Color{0xFF, 0, 0xFF, 0xA0}

draw_ui :: proc(ctx: ^GameCtx, delta_time: f32) {
	switch ctx.scene {
	case .Loading:
		default_font := rl.GetFontDefault()
		rl.DrawTextPro(
			default_font,
			"Loading",
			Vec2 {
				ctx.render_rect.x + (ctx.render_rect.width / 2),
				ctx.render_rect.y + (ctx.render_rect.height / 8),
			},
			Vec2{},
			0,
			32,
			1,
			rl.DARKGRAY,
		)
	case .Game:
		{ 	// draw UI
			GUI_TILE_SIZE :: 17
			rl.DrawRectangle(
				i32(ctx.render_rect.x),
				i32(ctx.render_rect.y),
				i32(GUI_TILE_SIZE * (9) * ctx.render_scale),
				i32(GUI_TILE_SIZE * (1) * ctx.render_scale),
				rl.GRAY,
			)

			for i in 0 ..< 9 {
				tile_size := GUI_TILE_SIZE * ctx.render_scale
				rl.DrawRectangleLinesEx(
					{
						f32(ctx.render_rect.x) + (f32(i) * tile_size),
						f32(ctx.render_rect.y),
						tile_size,
						tile_size,
					},
					1,
					rl.BLACK,
				)
			}


			MINIMAP_ZOOM_FACTOR :: 4
			minimap_size := (WORLD_SIZE / MINIMAP_ZOOM_FACTOR) * ctx.render_scale

			// rl.DrawPixel()
			rl.DrawTexturePro(
				ctx.world_texture,
				rl.Rectangle{0, 0, WORLD_SIZE, WORLD_SIZE},
				rl.Rectangle {
					ctx.render_rect.width - minimap_size,
					ctx.render_rect.y,
					minimap_size,
					minimap_size,
				},
				Vec2{},
				0,
				rl.WHITE,
			)
			rl.DrawRectangleLinesEx(
				{
					ctx.render_rect.width - minimap_size,
					ctx.render_rect.y,
					minimap_size,
					minimap_size,
				},
				1,
				rl.BLACK,
			)

			minimap_player_size := 2 * i32(ctx.render_scale)
			minimap_player_offset := (minimap_player_size / 2)
			minimap_player_scale := ctx.render_scale / (TILE_SIZE * MINIMAP_ZOOM_FACTOR)

			for _, p in ctx.players {
				player_entity, _ := entity_get(&ctx.entities, p.entity)
				rl.DrawRectangle(
					i32(ctx.render_rect.width - minimap_size) -
					minimap_player_offset +
					i32(player_entity.x * minimap_player_scale),
					i32(ctx.render_rect.y) -
					minimap_player_offset +
					i32(player_entity.y * minimap_player_scale),
					minimap_player_size,
					minimap_player_size,
					rl.PINK,
				)

				if false {
					default_font := rl.GetFontDefault()
					cstr := fmt.ctprintf(
						"%v(%v)",
						linalg.round(p.mouse_virtual_screen_position * 10) / 10,
						linalg.round(p.mouse_position_world * 10) / 10,
					)
					rl.DrawTextPro(
						default_font,
						cstr,
						{p.mouse_screen_position.x, p.mouse_screen_position.y - 10},
						0,
						0,
						10,
						1,
						rl.BLACK,
					)
				}
			}

		}
	case .MainMenu:
		get_btn_rect :: proc(
			id: f32,
			render_rect: rl.Rectangle,
			render_scale: f32,
		) -> rl.Rectangle {
			btn_width := 40 * render_scale
			btn_height := 20 * render_scale

			return {
				render_rect.x + (render_rect.width / 2) - btn_height,
				render_rect.y + (render_rect.height / 8) + id * btn_height * 1.2,
				btn_width,
				btn_height,
			}
		}

		if rl.GuiButton(get_btn_rect(0, ctx.render_rect, ctx.render_scale), "Play") {
			ctx.max_player_count = 1
			game_enter(ctx, &g_arena)
		}

		when PLATFORM == .STEAM {
			if rl.GuiButton(get_btn_rect(1, ctx.render_rect, ctx.render_scale), "Host") {
				steam.create_lobby(&ctx.steam)
			}
		}
	}


	if .DebugCross in ctx.flags {
		rl.DrawLineEx(
			{0, RENDER_HEIGHT / 2},
			{RENDER_WIDTH, RENDER_HEIGHT / 2},
			2,
			{80, 80, 80, 0x90},
		)
		rl.DrawLineEx(
			{RENDER_WIDTH / 2, 0},
			{RENDER_WIDTH / 2, RENDER_HEIGHT},
			2,
			{80, 80, 80, 0x90},
		)
	}
}

draw :: proc(ctx: ^GameCtx, delta_time: f32) {
	switch ctx.scene {
	case .Loading:
	case .Game:
		draw_game(ctx, delta_time)
	case .MainMenu:
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
	default_font := rl.GetFontDefault()


	{ 	// Render world
		rl.BeginMode2D(ctx.camera)
		defer rl.EndMode2D()

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
			switch entity.texture_id {
			case .None:
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
			case .Player:
				ANIMATION_DATA :: [?]struct {
					frame_count: i32,
					durrartion:  i32,
				}{{4, 500}}
				@(static) animation_frame := 0
				animation := 0
				switch entity.direction {

				}

				rl.DrawTexturePro(
					ctx.textures[.Player],
					rl.Rectangle {
						entity.size.x * f32(animation_frame),
						entity.size.y * f32(animation_frame),
						entity.size.x,
						entity.size.y,
					},
					rl.Rectangle {
						entity.position.x,
						entity.position.y,
						entity.size.x,
						entity.size.y,
					},
					0,
					0,
					rl.WHITE,
				)
			// animation_frame = (animation_frame + 1) % 4
			case .Bullet:
			// rl.DrawLineEx(entity.position, entity.velocity, 1, rl.BLACK)

			}

			cstr := fmt.ctprintf("%v:%v", i, entity.generation)
			rl.DrawTextPro(
				default_font,
				cstr,
				rl.Vector2{entity.position.x, entity.position.y - 10},
				Vec2{},
				0,
				10,
				1,
				rl.BLACK,
			)
		}
	}

}
