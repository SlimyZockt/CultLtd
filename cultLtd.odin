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
import "core:prof/spall"
import "core:sync"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import ase "./aseprite"
import steam "./steam/"

import "vendor:ggpo"

LOGIC_FPS :: 60
LOGIC_TICK_RATE :: 1.0 / LOGIC_FPS
NET_TICK_RATE :: 1.0 / 30

LOG_PATH :: "berry.logs"
STEAM :: #config(STEAM, false)


EntityFlagBits :: enum u32 {
	Controlabe,
	Camera,
	Sync,
	Alive,
	// Non;,
}

EntityFlags :: bit_set[EntityFlagBits;u32]

TextureId :: distinct u64

EntityHandle :: struct {
	id:         u64,
	generation: u64,
}

Entity :: struct {
	generation:        u64,
	speed:             f32,
	flags:             EntityFlags,
	texture_id:        TextureId,
	using pos:         [2]f32,
	size:              [2]f32,
	NextFreeEntityIdx: Maybe(u64),
}

EntityList :: struct {
	list:          [dynamic]Entity,
	FreeEntityIdx: Maybe(u64),
}

CultCtxFlagBits :: enum u32 {
	DebugCross,
	Server,
	Client,
}

CultCtxFlags :: bit_set[CultCtxFlagBits;u32]

Actions :: enum u8 {
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

MaxPlayerCount :: 4
MaxInputQueue :: 8
ActionToggles :: bit_set[Actions;u32]
Player :: struct {
	input_down:    ActionToggles,
	input_pressed: ActionToggles,
	id:            u64,
}

RenderCtx :: struct {
	scene:       Scenes,
	render_size: [2]f32,
	cameras:     []rl.Camera2D,
	textures:    [dynamic]rl.Texture,
}

CultCtx :: struct {
	player_id:        u8,
	player_count:     u8,
	flags:            CultCtxFlags,
	using render_ctx: RenderCtx,
	entities:         EntityList,
	keymap:           [Actions]rl.KeyboardKey,
	lobby:            [MaxPlayerCount]Player,
}

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

entity_add :: proc(
	entities: ^EntityList,
	entity: Entity,
	allocator := context.allocator,
) -> EntityHandle {


	if idx, ok := entities.FreeEntityIdx.?; ok {
		generation := entities.list[idx].generation + 1
		entities.FreeEntityIdx = entities.list[idx].NextFreeEntityIdx

		entities.list[idx].flags += {.Alive}
		entities.list[idx] = entity
		entities.list[idx].NextFreeEntityIdx = nil
		entities.list[idx].generation = generation

		return EntityHandle{idx, generation}
	}


	assert(entity.generation == 0)
	assert(entity.NextFreeEntityIdx == nil)

	append(&entities.list, entity)
	idx := len(entities.list) - 1
	entities.list[idx].flags += {.Alive}
	assert(.Alive in entities.list[idx].flags)
	return EntityHandle{u64(idx), 0}
}

entity_delete :: proc(entities: ^EntityList, entity_handle: EntityHandle) {
	if entities.list[entity_handle.id].generation != entity_handle.generation {
		log.error("delete not existing element")
		return
	}
	entities.list[entity_handle.id].generation += 1

	entities.list[entity_handle.id].NextFreeEntityIdx = entities.FreeEntityIdx
	entities.FreeEntityIdx = entity_handle.id
}

entity_get :: proc(entities: ^EntityList, entity_handle: EntityHandle) -> ^Entity {
	if entities.list[entity_handle.id].generation != entity_handle.generation {
		log.error("Wrong generation entity")
		return nil
	}

	return &entities.list[entity_handle.id]
}

HEADLESS :: #config(HEADLESS, false)

// Global
g_cult_debug := #config(CULT_DEBUG, ODIN_DEBUG)
g_ctx: runtime.Context
g_arena: vmem.Arena
g_spall_ctx: spall.Context
g_game_ctx := CultCtx {
	flags        = {},
	scene        = .MainMenu,
	player_count = 1,
	player_id    = 0,
}

@(thread_local)
spall_buffer: spall.Buffer

@(instrumentation_enter)
spall_enter :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	spall._buffer_begin(&g_spall_ctx, &spall_buffer, "", "", loc)
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	spall._buffer_end(&g_spall_ctx, &spall_buffer)
}


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
	steam.g_ctx = context

	g_spall_ctx = spall.context_create("trace.spall")
	defer spall.context_destroy(&g_spall_ctx)


	buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	defer delete(buffer_backing)

	spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
	defer spall.buffer_destroy(&g_spall_ctx, &spall_buffer)


	when ODIN_DEBUG {
		rl.SetConfigFlags({.BORDERLESS_WINDOWED_MODE})
	} else {
		rl.SetConfigFlags({.FULLSCREEN_MODE, .BORDERLESS_WINDOWED_MODE})
	}

	rl.SetTraceLogLevel(.ALL)
	rl.SetTraceLogCallback(rl_trace_to_log)
	rl.InitWindow(0, 0, "CultLtd.")
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 30)
	rl.SetTargetFPS(500)
	defer rl.CloseWindow()
	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)

	monitor_id: i32
	monitor_count := rl.GetMonitorCount()
	g_game_ctx.render_size.y = f32(rl.GetMonitorHeight(0))
	for i in 0 ..= monitor_count {
		new_height := f32(rl.GetMonitorHeight(i))
		if g_game_ctx.render_size.y < new_height {
			monitor_id = i
			g_game_ctx.render_size.y = new_height
		}
	}
	g_game_ctx.render_size.x = f32(rl.GetMonitorWidth(monitor_id))
	g_game_ctx.render_size /= f32(2)
	rl.SetWindowSize(i32(g_game_ctx.render_size.x), i32(g_game_ctx.render_size.y))
	rl.SetWindowMonitor(monitor_id)

	// ctx.lobby = make(map[u64]Player)
	g_game_ctx.entities.FreeEntityIdx = nil
	g_game_ctx.entities.list = make([dynamic]Entity, 0, 128)
	{ 	// set up default keybindings
		g_game_ctx.keymap[.DebugCross] = .F2
		g_game_ctx.keymap[.UP] = .W
		g_game_ctx.keymap[.DOWN] = .S
		g_game_ctx.keymap[.RIGHT] = .D
		g_game_ctx.keymap[.LEFT] = .A
		g_game_ctx.keymap[.INTERACT] = .E
	}
	g_game_ctx.cameras = {{offset = g_game_ctx.render_size / 2, zoom = 1}}
	defer vmem.arena_destroy(&g_arena)

	entity_add(
		&g_game_ctx.entities,
		Entity{flags = {.Controlabe, .Camera}, speed = 500, size = {32, 64}},
	)

	elapsed_logic_time: f32
	elapsed_net_time: f32

	when STEAM {
		// steam_ctx: steam.SteamCtx
		steam.g_steam.on_lobby_enter = proc(ctx: steam.SteamCtx) {
			g_game_ctx.scene = .Game
			entity_add(
				&g_game_ctx.entities,
				Entity{flags = {.Sync, .Controlabe}, size = {16, 32}, speed = 500},
			)
		}
		steam.init(&steam.g_steam)

	}
	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		elapsed_logic_time += delta_time
		elapsed_net_time += delta_time

		update_input(LOGIC_TICK_RATE, &g_game_ctx)

		for elapsed_net_time >= NET_TICK_RATE {
			elapsed_net_time -= NET_TICK_RATE
			when STEAM {
				steam.upadate_callback(&steam.g_steam, &g_arena)

			}


			if .Server in g_game_ctx.flags {
				// logic_update_server()
			} else {
				// logic_update_client()
			}

		}


		for elapsed_logic_time >= LOGIC_TICK_RATE {
			elapsed_logic_time -= LOGIC_TICK_RATE
			upadate_logic(LOGIC_TICK_RATE, &g_game_ctx)
		}


		{ 	// Render
			rl.BeginDrawing()
			rl.ClearBackground(rl.WHITE)
			defer rl.EndDrawing()

			upadate_render(delta_time, &g_game_ctx)

			rl.DrawFPS(0, 0)
		}
		spall.SCOPED_EVENT(&g_spall_ctx, &spall_buffer, #procedure)

	}

	when STEAM {
		steam.destroy(steam.g_steam)
	}

}

update_input :: proc(delta_time: f32, ctx: ^CultCtx) {
	input := &ctx.lobby[ctx.player_id].input_down

	input^ = rl.IsKeyDown(ctx.keymap[.UP]) ? input^ + {.UP} : input^ - {.UP}
	input^ = rl.IsKeyDown(ctx.keymap[.DOWN]) ? input^ + {.DOWN} : input^ - {.DOWN}
	input^ = rl.IsKeyDown(ctx.keymap[.LEFT]) ? input^ + {.LEFT} : input^ - {.LEFT}
	input^ = rl.IsKeyDown(ctx.keymap[.RIGHT]) ? input^ + {.RIGHT} : input^ - {.RIGHT}


	if rl.IsKeyPressed(ctx.keymap[.DebugCross]) {
		if .DebugCross in ctx.flags {
			ctx.flags -= {.DebugCross}
		} else {
			ctx.flags += {.DebugCross}
		}
	}
}

upadate_logic :: proc(delta_time: f32, ctx: ^CultCtx) {
	for &entity in ctx.entities.list {
		if (EntityFlags{.Controlabe} <= entity.flags) { 	// movement ctl
			input: [2]f32

			input_down := ctx.lobby[ctx.player_id].input_down
			if .UP in input_down do input.y -= 1
			if .DOWN in input_down do input.y += 1
			if .RIGHT in input_down do input.x += 1
			if .LEFT in input_down do input.x -= 1

			if input.x != 0 || input.y != 0 {
				dir := linalg.normalize(input)
				entity.pos += dir * entity.speed * LOGIC_TICK_RATE
			}
		}
	}

}

upadate_render :: proc(delta_time: f32, ctx: ^CultCtx) {
	switch ctx.scene {
	case .Game:
		update_game_scene(delta_time, ctx)
	case .MainMenu:
		if rl.GuiButton(
			rl.Rectangle{(ctx.render_size.x / 2) - 100, (0 + ctx.render_size.y / 4), 200, 60},
			"Play",
		) {
			ctx.scene = .Game
		}
		when STEAM {
			x := (ctx.render_size.x / 2) - 100
			y := (0 + ctx.render_size.y / 4) + 70
			if rl.GuiButton(rl.Rectangle{x, y, 200, 60}, "Host") {
				steam.host(&steam.g_steam)


				ctx.scene = .Game
				assert(.Client not_in ctx.flags)
				ctx.flags += {.Server}
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

update_game_scene :: proc(delta_time: f32, ctx: ^CultCtx) {
	for &entity in ctx.entities.list {
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


}
