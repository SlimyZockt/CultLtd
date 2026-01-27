// Sacrifice other world beings to grow your factory
package main

import "base:runtime"
import "core:c"
import "core:container/queue"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:math/linalg"
import vmem "core:mem/virtual"
import old_os "core:os"
import os "core:os/os2"
import "core:prof/spall"
import "core:sync"
import "vendor:ENet"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import ase "./aseprite"
import steam "./steam/"

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
	arena:         vmem.Arena,
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
	Loading,
}

ActionToggles :: bit_set[Actions;u32]
Player :: struct {
	input_down:    ActionToggles,
	input_pressed: ActionToggles,
	enitty:        EntityHandle,
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
	players:          []Player,
	steam:            steam.SteamCtx,
}


LOG_PATH :: "berry.logs"
STEAM :: #config(STEAM, true)
HEADLESS :: #config(HEADLESS, false)

LOGIC_FPS :: 60
LOGIC_TICK_RATE :: 1.0 / LOGIC_FPS
NET_TICK_RATE :: 1.0 / 30
MAX_PLAYER_COUNT :: 8
// Global
g_cult_debug := #config(CULT_DEBUG, ODIN_DEBUG)
g_ctx: runtime.Context
g_arena: vmem.Arena
g_spall_ctx: spall.Context

@(thread_local)
spall_buffer: spall.Buffer

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

entity_get :: proc(entities: EntityList, entity_handle: EntityHandle) -> ^Entity {
	if entities.list[entity_handle.id].generation != entity_handle.generation {
		log.error("Wrong generation entity")
		return nil
	}

	return &entities.list[entity_handle.id]
}

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

	g_spall_ctx = spall.context_create("trace.spall")
	defer spall.context_destroy(&g_spall_ctx)


	buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	defer delete(buffer_backing)

	spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
	defer spall.buffer_destroy(&g_spall_ctx, &spall_buffer)

	@(static) ctx := CultCtx {
		flags = {},
		scene = .MainMenu,
		player_count = 1,
		player_id = 0,
		keymap = {
			.DebugCross = .F2,
			.UP = .W,
			.DOWN = .S,
			.RIGHT = .D,
			.LEFT = .A,
			.INTERACT = .E,
		},
	}

	when STEAM {
		steam.init(&ctx.steam)
	}

	// Setup Engine
	when ODIN_DEBUG {
		rl.SetConfigFlags({.BORDERLESS_WINDOWED_MODE})
	} else {
		rl.SetConfigFlags({.FULLSCREEN_MODE, .BORDERLESS_WINDOWED_MODE})
	}

	rl.SetTraceLogLevel(.ALL)
	// rl.SetTraceLogCallback(rl_trace_to_log)
	rl.InitWindow(0, 0, "CultLtd.")
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 30)
	rl.SetTargetFPS(500)
	defer rl.CloseWindow()
	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)


	monitor_id: i32
	monitor_count := rl.GetMonitorCount()
	ctx.render_size.y = f32(rl.GetMonitorHeight(0))
	for i in 0 ..= monitor_count {
		new_height := f32(rl.GetMonitorHeight(i))
		if ctx.render_size.y < new_height {
			monitor_id = i
			ctx.render_size.y = new_height
		}
	}
	ctx.render_size.x = f32(rl.GetMonitorWidth(monitor_id))
	ctx.render_size /= f32(2)
	rl.SetWindowSize(i32(ctx.render_size.x), i32(ctx.render_size.y))
	rl.SetWindowMonitor(monitor_id)

	ctx.cameras = {{offset = ctx.render_size / 2, zoom = 1}}
	defer vmem.arena_destroy(&g_arena)

	elapsed_logic_time: f32
	elapsed_net_time: f32

	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		elapsed_logic_time += delta_time
		elapsed_net_time += delta_time

		update_input(&ctx, LOGIC_TICK_RATE)

		for elapsed_net_time >= NET_TICK_RATE {
			elapsed_net_time -= NET_TICK_RATE
			when STEAM {
				steam.update_callback(&ctx.steam, &g_arena)
				for ctx.steam.event_queue.len > 0 {
					event := queue.pop_front(&ctx.steam.event_queue)
					switch event {
					case .Connecting:
						ctx.scene = .Loading
					case .Connected:
						game_init(&ctx, MAX_PLAYER_COUNT)
					case .Disconnected:
					case .PeerConnected:
					case .PeerDisconnected:

					}
				}
			}

			if ctx.scene != .MainMenu {
				// net_update(&ctx)
			}
		}

		for elapsed_logic_time >= LOGIC_TICK_RATE {
			elapsed_logic_time -= LOGIC_TICK_RATE
			update_logic(&ctx, LOGIC_TICK_RATE)
		}

		{ 	// Render
			rl.BeginDrawing()
			rl.ClearBackground(rl.WHITE)
			defer rl.EndDrawing()

			update_render(&ctx, delta_time)

			rl.DrawFPS(0, 0)
		}
		spall.SCOPED_EVENT(&g_spall_ctx, &spall_buffer, #procedure)

	}

	when STEAM {
		steam.destroy(ctx.steam)
	}
}

update_input :: proc(ctx: ^CultCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	input := &ctx.players[ctx.player_id].input_down

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

update_logic :: proc(ctx: ^CultCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	for &entity in ctx.entities.list {
		if (EntityFlags{.Controlabe} <= entity.flags) { 	// movement ctl
			input: [2]f32

			input_down := ctx.players[ctx.player_id].input_down
			if .UP in input_down do input.y -= 1
			if .DOWN in input_down do input.y += 1
			if .RIGHT in input_down do input.x += 1
			if .LEFT in input_down do input.x -= 1

			if input.x != 0 || input.y != 0 {
				dir := linalg.normalize(input)
				entity.pos += dir * entity.speed * delta_time
			}
		}
	}

}

update_render :: proc(ctx: ^CultCtx, delta_time: f32) {
	switch ctx.scene {
	case .Loading:
		rl.DrawText(
			"Loading",
			i32(ctx.render_size.x / 2),
			i32(ctx.render_size.y / 2),
			32,
			rl.DARKGRAY,
		)


	case .Game:
		update_game_render(ctx, delta_time)
	case .MainMenu:
		get_ui_pos :: proc(render_size: [2]f32, i: f32) -> [2]f32 {
			return {(render_size.x / 2) - 100, (render_size.y / 4) + i * 70}
		}

		btn_pos := get_ui_pos(ctx.render_size, 0)
		if rl.GuiButton(rl.Rectangle{btn_pos.x, btn_pos.y, 200, 60}, "Play") {
			game_init(ctx)
		}

		when STEAM {
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

update_game_render :: proc(ctx: ^CultCtx, delta_time: f32) {
	// player := entity_get(ctx.entities, ctx.player)
	// ctx.cameras[0].target = player.pos + (player.size / 2)


	{ 	// Render UI

	}

	//HACK(abdul): update cam pos before draw cam
	for &entity in ctx.entities.list {
		if .Camera in entity.flags {
			ctx.cameras[0].target = entity.pos + (entity.size / 2)
		}
	}

	{ 	// Render world
		rl.BeginMode2D(ctx.cameras[0])
		defer rl.EndMode2D()

		rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)

		for &entity in ctx.entities.list {
			rl.DrawRectanglePro(
				rl.Rectangle{entity.pos.x, entity.pos.y, entity.size.x, entity.size.y},
				[2]f32{},
				0,
				rl.RED,
			)
		}
	}
}


game_init :: proc(ctx: ^CultCtx, max_player_count := 1, allocator := context.allocator) {
	assert(max_player_count > 0)
	assert(max_player_count <= MAX_PLAYER_COUNT)
	ctx.scene = .Game
	ctx.players = make([]Player, max_player_count, allocator)
	if ctx.player_count == 1 {
		ctx.flags += {.Server}
		ctx.players[0].id = 0
	} else {

	}

	err := vmem.arena_init_growing(&ctx.entities.arena)
	ensure(err == nil)
	entities_alloc := vmem.arena_allocator(&ctx.entities.arena)
	ctx.entities = {
		FreeEntityIdx = nil,
		list          = make([dynamic]Entity, 0, 128, entities_alloc),
	}

	entity_add(&ctx.entities, Entity{flags = {.Controlabe, .Camera}, speed = 500, size = {32, 64}})

	for i in 0 ..< (ctx.player_count - 1) {
		entity_add(
			&ctx.entities,
			Entity{flags = {.Controlabe}, speed = 500, size = {32, 64}, pos = {0, 0}},
		)
	}
}

game_deinit :: proc(ctx: ^CultCtx) {
	vmem.arena_destroy(&ctx.entities.arena)
}
