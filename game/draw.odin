package game

import "core:container/xar"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import vmem "core:mem/virtual"
import "core:reflect"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "../steam"

GHOST_COLOR :: Color{0xFF, 0, 0xFF, 0xA0}
DEBUG_COLOR :: Color{80, 80, 80, 0x90}

draw_ui :: proc(ctx: ^GameCtx, delta_time: f32) {
	padding := 2 * ctx.render_scale
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
		top_right := ctx.render_rect.x + ctx.render_rect.width
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
					top_right - minimap_size,
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
				mouse_position_world := rl.GetScreenToWorld2D(
					p.mouse_virtual_screen_position,
					ctx.camera,
				)
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
						linalg.round(mouse_position_world * 10) / 10,
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

			local_player, ok := ctx.players[ctx.player_id]
			assert(ok)
			// local_player_entity, ok2 := entity_get(&ctx.entities, local_player.entity)
			//          assert(ok2)
			if .DebugMenu in local_player.input_toggled {
				defer rl.GuiSetStyle(
					.DEFAULT,
					i32(rl.GuiDefaultProperty.TEXT_SIZE),
					i32(math.floor(10 * g_game_ctx.render_scale)),
				)
				btn_width := 60 * ctx.render_scale
				btn_height := 11 * ctx.render_scale
				RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT :: 24 // see raygui.c (https://github.com/raysan5/raygui/blob/master/src/raygui.h#L1648)
				rl.GuiSetStyle(
					.DEFAULT,
					i32(rl.GuiDefaultProperty.TEXT_SIZE),
					RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT,
				)
				rl.GuiPanel(
					{
						top_right - btn_width,
						ctx.render_rect.y,
						btn_width + padding,
						btn_height *
							len(
								DebugOptionBits,
							) + 2 * padding + RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT, // f32(text_size) +
					},
					"Debug Menu",
				)

				rl.GuiSetStyle(
					.DEFAULT,
					i32(rl.GuiDefaultProperty.TEXT_SIZE),
					i32(5 * g_game_ctx.render_scale),
				)
				alloc := vmem.arena_allocator(&g_arena)
				temp := vmem.arena_temp_begin(&g_arena)
				defer vmem.arena_temp_end(temp)
				for debug_option, i in DebugOptionBits {
					active := debug_option in ctx.debug_options
					display_name, _ := reflect.enum_name_from_value(debug_option)
					rl.GuiToggle(
						{
							top_right - btn_width + padding,
							ctx.render_rect.y + padding + btn_height * f32(i) + RAYGUI_WINDOWBOX_STATUSBAR_HEIGHT, // f32(text_size) +
							btn_width - padding * 2,
							btn_height,
						},
						strings.clone_to_cstring(display_name, alloc),
						&active,
					)
					if debug_option in ctx.debug_options != active {
						ctx.debug_options ~= {debug_option}
					}
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
	default_font := rl.GetFontDefault()


	{ 	// Render world
		rl.BeginMode2D(ctx.camera)
		defer rl.EndMode2D()

		// assert(ctx.world_shader.locs != nil, "Shader missing")
		rl.DrawTexturePro(
			ctx.world_texture,
			rl.Rectangle{0, 0, WORLD_SIZE, WORLD_SIZE},
			rl.Rectangle{0, 0, WORLD_SIZE * TILE_SIZE, WORLD_SIZE * TILE_SIZE},
			0,
			0,
			rl.WHITE,
		)

		if .Grid in ctx.debug_options { 	// GRID
			rlgl.PushMatrix()
			rlgl.Translatef(WORLD_SIZE * TILE_SIZE, WORLD_SIZE * TILE_SIZE, 0)
			rlgl.Rotatef(90, 1, 0, 0)
			rl.DrawGrid(2 * WORLD_SIZE, TILE_SIZE)
			rlgl.PopMatrix()
		}

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
					entity.size / 2,
					0,
					entity.tint,
				)
			case .Player:
				// FIX: switch to a general animation system
				@(static) animation_frame: i32 = 0
				@(static) eleapsed_time: f32 = 0
				@(static) animation: f32 = 0
				@(static) flip_x: f32 = 1
				moving: f32

				if entity.direction.x == 0 {
					switch entity.direction.y {
					case 1:
						animation = 2
					case -1:
						animation = 4
					}
				} else {
					if entity.direction.x >= 0 { 	// Right
						animation = 0
						flip_x = 1
					}
					if entity.direction.x < 0 { 	// Left
						animation = 0
						flip_x = -1
					}
				}

				if .Moving in entity.flags {
					moving = 1
				}
				// log.debug(entity.flags)

				eleapsed_time += delta_time
				if eleapsed_time >= 0.100 {
					eleapsed_time = 0
					animation_frame = (animation_frame + 1) % 4
				}

				rl.DrawTexturePro(
					ctx.textures[.Player],
					rl.Rectangle {
						entity.size.x * (4 * (animation + moving) + f32(animation_frame)),
						entity.size.y,
						entity.size.x * flip_x,
						entity.size.y,
					},
					rl.Rectangle {
						entity.position.x,
						entity.position.y,
						entity.size.x,
						entity.size.y,
					},
					entity.size / 2,
					0,
					entity.tint,
				)
			// animation_frame = (animation_frame + 1) % 4
			case .Bullet:
			// rl.DrawLineEx(entity.position, entity.velocity, 1, rl.BLACK)

			}

			if .ShowEntityHandle in ctx.debug_options {
				cstr := fmt.ctprintf("%v:%v", i, entity.generation)
				rl.DrawTextPro(
					default_font,
					cstr,
					rl.Vector2{entity.position.x, entity.position.y - 10},
					entity.size / 2,
					0,
					10,
					1,
					rl.BLACK,
				)
			}
		}

		if .LineToMouse in ctx.debug_options {
			local_player, ok := ctx.players[ctx.player_id]
			assert(ok)
			local_player_entity, _ := entity_get(&ctx.entities, local_player.entity)
			mouse_position_world := rl.GetScreenToWorld2D(
				local_player.mouse_virtual_screen_position,
				ctx.camera,
			)
			rl.DrawLineEx(local_player_entity.position, mouse_position_world, 1, DEBUG_COLOR)
		}
	}


	if .Cross in ctx.debug_options {
		rl.DrawLineEx({0, RENDER_HEIGHT / 2}, {RENDER_WIDTH, RENDER_HEIGHT / 2}, 2, DEBUG_COLOR)
		rl.DrawLineEx({RENDER_WIDTH / 2, 0}, {RENDER_WIDTH / 2, RENDER_HEIGHT}, 2, DEBUG_COLOR)
	}

}
