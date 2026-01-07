// Sacrifice other world beings to grow your factory
package main

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:flags"
import "core:log"
import "core:math/linalg"
import vmem "core:mem/virtual"
import old_os "core:os"
import os "core:os/os2"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import ase "./aseprite"
import steam "./steamworks/"

import "vendor:ggpo"

LOGIC_FPS :: 60
LOGIC_TICK_RATE :: 1.0 / LOGIC_FPS
// STEAM_TICK_RATE :: 1.0 / 20

LOG_PATH :: "berry.logs"
STEAM :: #config(STEAM, false)

rl_trace_to_log :: proc "c" (rl_level: rl.TraceLogLevel, message: cstring, args: ^c.va_list) {
	context = g_ctx

	level: log.Level
	switch rl_level {
	case .TRACE, .DEBUG:
		level = .Debug
	case .INFO:
		level = .Info
	case .WARNING:
		level = .Warning
	case .ERROR:
		level = .Error
	case .FATAL:
		level = .Fatal
	case .ALL, .NONE:
		fallthrough
	case:
		log.panicf("unexpected log level %v", rl_level)
	}

	@(static) buf: [dynamic]byte
	log_len: i32
	for {
		buf_len := i32(len(buf))
		log_len = stbsp.vsnprintf(raw_data(buf), buf_len, message, args)
		if log_len <= buf_len {
			break
		}

		non_zero_resize(&buf, max(128, len(buf) * 2))
	}

	context.logger.procedure(
		context.logger.data,
		level,
		string(buf[:log_len]),
		context.logger.options,
	)
}


EntityFlagBits :: enum u32 {
	Controlabe,
	Camera,
	// Non;,
}

EntityFlags :: bit_set[EntityFlagBits;u32]

EntityId :: distinct u64
TextureId :: distinct u64

Entity :: struct {
	generation: u32,
	speed:      f32,
	flags:      EntityFlags,
	id:         EntityId,
	texture_id: TextureId,
	using pos:  [2]f32,
	size:       [2]f32,
	// vel:       [2]f32,
}

CultCtxFlagBits :: enum u32 {
	DebugCross,
	Server,
}

CultCtxFlags :: bit_set[CultCtxFlagBits;u32]

KeyActions :: enum u8 {
	DebugCross,
	UP,
	DOWN,
	LEFT,
	RIGHT,
	INTERACT,
}

Scenes :: enum u32 {
	Game,
	MainMenu,
}


RenderCtx :: struct {
	scene:       Scenes,
	render_size: [2]f32,
	cameras:     []rl.Camera2D,
	textures:    [dynamic]rl.Texture,
}

GameCtx :: struct {
	entities: [dynamic]Entity,
}

CultCtx :: struct {
	flags:            CultCtxFlags,
	using game_ctx:   GameCtx,
	using render_ctx: RenderCtx,
	using steam:      SteamCtx,
	keymap:           [KeyActions]rl.KeyboardKey,
}


HEADLESS :: #config(HEADLESS, false)

// Global
g_cult_debug := #config(CULT_DEBUG, ODIN_DEBUG)
g_ctx: runtime.Context
g_arena: vmem.Arena

main :: proc() {
	g_ctx = context
	if g_cult_debug {
		if !os.exists(LOG_PATH) {
			_, err := os.create(LOG_PATH)
			ensure(err == nil, "failed to create log file")
		}

		handle, err := old_os.open(LOG_PATH, old_os.O_RDWR, 0o666)
		ensure(err == nil)

		g_ctx.logger = log.create_multi_logger(
			log.create_file_logger(handle),
			log.create_console_logger(),
		)

		ase.genereate_png_from_ase("aseprite", "./assets/")
	}
	context = g_ctx


	when ODIN_DEBUG {
		rl.SetConfigFlags({.BORDERLESS_WINDOWED_MODE})
	} else {
		rl.SetConfigFlags({.FULLSCREEN_MODE, .BORDERLESS_WINDOWED_MODE})
	}

	rl.SetTraceLogLevel(.ALL)
	rl.SetTraceLogCallback(rl_trace_to_log)
	rl.InitWindow(0, 0, "CultLtd.")
	defer rl.CloseWindow()

	ctx: CultCtx

	when STEAM {
		steam_init(&ctx.steam)
	}

	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)

	monitor_id: i32
	monitor_count := rl.GetMonitorCount()
	monitor_height := rl.GetMonitorHeight(0)
	for i in 0 ..= monitor_count {
		new_height := rl.GetMonitorHeight(i)
		if monitor_height < new_height {
			monitor_id = i
			monitor_height = new_height
		}
	}
	rl.SetWindowMonitor(monitor_id)

	ctx.render_size = {f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
	ctx.flags = {}
	ctx.scene = .MainMenu
	ctx.entities = make([dynamic]Entity, 0, 128)
	{ 	// set up default keybindings
		ctx.keymap[.DebugCross] = .F2
		ctx.keymap[.UP] = .W
		ctx.keymap[.DOWN] = .S
		ctx.keymap[.RIGHT] = .D
		ctx.keymap[.LEFT] = .A
		ctx.keymap[.INTERACT] = .E
	}
	ctx.cameras = {{offset = ctx.render_size / 2, zoom = 1}}
	defer vmem.arena_destroy(&g_arena)

	append(
		&ctx.entities,
		Entity {
			flags = {.Controlabe, .Camera},
			speed = 500,
			size = {32, 64},
			id = #hash("player", "fnv32a"),
		},
	)
	elapsed_time: f32

	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 30)

	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		elapsed_time += delta_time

		for elapsed_time >= LOGIC_TICK_RATE {
			elapsed_time -= LOGIC_TICK_RATE
			when STEAM {
				steam_callback_upadate(&ctx, &g_arena)
			}
			//TODO(abdul): sync server
			if .Server in ctx.flags {
				// logic_update_server()
			} else {
				// logic_update_client()

			}
			logic_upadate_shared(LOGIC_TICK_RATE, &ctx)
		}


		{ 	// Render
			rl.BeginDrawing()
			rl.ClearBackground(rl.WHITE)
			defer rl.EndDrawing()

			render_upadate(delta_time, &ctx)

			rl.DrawFPS(0, 0)
		}
	}

	when STEAM {
		steam_destroy()
	}
}


logic_upadate_shared :: proc(delta_time: f32, ctx: ^CultCtx) {
	for &entity in ctx.entities {
		if .Controlabe in entity.flags { 	// movement ctl

			input: [2]f32
			if rl.IsKeyDown(ctx.keymap[.UP]) do input.y -= 1
			if rl.IsKeyDown(ctx.keymap[.DOWN]) do input.y += 1
			if rl.IsKeyDown(ctx.keymap[.RIGHT]) do input.x += 1
			if rl.IsKeyDown(ctx.keymap[.LEFT]) do input.x -= 1

			if input.x != 0 || input.y != 0 {
				dir := linalg.normalize(input)
				entity.pos += dir * entity.speed * LOGIC_TICK_RATE
			}
		}
	}


}


render_upadate :: proc(delta_time: f32, ctx: ^CultCtx) {
	switch ctx.scene {
	case .Game:
		render_game(delta_time, ctx)
	case .MainMenu:
		if rl.GuiButton(
			rl.Rectangle{ctx.render_size.x / 2, (0 + ctx.render_size.y / 4), 200, 60},
			"Play",
		) {
			ctx.scene = .Game
		}
		when STEAM {
			if rl.GuiButton(
				rl.Rectangle{ctx.render_size.x / 2, (0 + ctx.render_size.y / 4) + 70, 200, 60},
				"Host",
			) {
				_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, 4)
				ctx.scene = .Game
			}
			if rl.GuiButton(
				rl.Rectangle{ctx.render_size.x / 2, (0 + ctx.render_size.y / 4) + 140, 200, 60},
				"Join",
			) {
				// _ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .Private, 4)
				ctx.scene = .Game
			}
		}
	}

}

render_game :: proc(delta_time: f32, ctx: ^CultCtx) {
	if rl.IsKeyPressed(ctx.keymap[.DebugCross]) {
		if .DebugCross in ctx.flags {
			ctx.flags -= {.DebugCross}
		} else {
			ctx.flags += {.DebugCross}
		}
	}


	for &entity in ctx.entities {
		if .Camera in entity.flags {
			ctx.cameras[0].target = entity.pos + (entity.size / 2)
			rl.BeginMode2D(ctx.cameras[0])
			defer rl.EndMode2D()

			rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)


			rl.DrawRectanglePro(
				rl.Rectangle{entity.pos.x, entity.pos.y, entity.size.x, entity.size.y},
				[2]f32{},
				0,
				rl.RED,
			)
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
