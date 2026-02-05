// Sacrifice other world beings to grow your factory
package main

import "base:runtime"
import "core:c"
import "core:container/queue"
import "core:container/xar"
import "core:fmt"
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
import steamworks "./vendor/steamworks/"

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
	list:          xar.Array(Entity, 4),
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
	Up,
	Down,
	Left,
	Right,
	Interact,
	Quit,
}

Scenes :: enum u32 {
	Game,
	MainMenu,
	Loading,
}

ActionToggles :: distinct bit_set[Actions;u32]
PlayerID :: distinct u64
Player :: struct {
	input_down:    ActionToggles,
	input_pressed: ActionToggles,
	entity:        EntityHandle,
}


RenderCtx :: struct {
	scene:       Scenes,
	render_size: [2]f32,
	cameras:     []rl.Camera2D,
	textures:    [dynamic]rl.Texture,
}

CultCtx :: struct {
	player_count:     u16,
	max_player_count: u16,
	flags:            CultCtxFlags,
	player_id:        PlayerID,
	using render_ctx: RenderCtx,
	entities:         EntityList,
	keymap:           [Actions]rl.KeyboardKey,
	players:          map[PlayerID]Player,
	steam:            steam.SteamCtx,
}

NetData :: struct {
	id:            PlayerID,
	player:        Player,
	player_entity: Entity,
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

PLAYER_ENTITY :: Entity {
	flags = {.Controlabe},
	speed = 500,
	size  = {32, 64},
}

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

entity_add :: proc(entities: ^EntityList, entity: Entity) -> EntityHandle {
	if idx, ok := entities.FreeEntityIdx.?; ok {
		new_entity := xar.get_ptr(&entities.list, idx)
		generation := new_entity.generation
		entities.FreeEntityIdx = new_entity.NextFreeEntityIdx

		new_entity^ = entity
		// new_entity.flags += {.Alive}
		new_entity.NextFreeEntityIdx = nil
		new_entity.generation = generation

		return EntityHandle{idx, generation}
	}


	assert(entity.generation == 0)
	assert(entity.NextFreeEntityIdx == nil)
	xar.append(&entities.list, entity)

	idx := entities.list.len - 1
	return EntityHandle{u64(idx), 0}
}

entity_delete :: proc(entities: ^EntityList, entity_handle: EntityHandle) {
	entity := xar.get_ptr(&entities.list, entity_handle.id)
	if entity.generation != entity_handle.generation {
		log.errorf("try to delete an not existing element %v", entity_handle)
		return
	}

	entity.generation += 1
	entity.NextFreeEntityIdx = entities.FreeEntityIdx
	entities.FreeEntityIdx = entity_handle.id
}

@(rodata)
ENTITY_ZERO: Entity

entity_get :: proc(entities: ^EntityList, entity_handle: EntityHandle) -> ^Entity {
	if int(entity_handle.id) >= entities.list.len do return &ENTITY_ZERO
	entity := xar.get_ptr(&entities.list, entity_handle.id)
	if entity.generation != entity_handle.generation {
		log.error("Wrong generation entity")
		return &ENTITY_ZERO
	}

	return entity
}

@(require_results)
entity_set :: proc(entities: ^EntityList, entity_handle: EntityHandle, entity: Entity) -> bool {
	if int(entity_handle.id) >= entities.list.len do return false
	old_entity := xar.get_ptr(&entities.list, entity_handle.id)
	if old_entity.generation != entity_handle.generation {
		log.error("Wrong generation entity")
		return false
	}

	xar.set(&entities.list, entity_handle.id, entity)
	return true
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
			.Up = .W,
			.Down = .S,
			.Right = .D,
			.Left = .A,
			.Interact = .E,
			.Quit = .F1,
		},
	}

	// Setup Engine
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
	ctx.render_size.y = f32(rl.GetMonitorHeight(0))
	for i in 0 ..< monitor_count {
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


	on_receive_msg :: proc(msg: ^steamworks.SteamNetworkingMessage) {
		data := (^NetData)(msg.pData)

		if data.id != PlayerID(ctx.steam.steam_id) {
			if _, exists := ctx.players[data.id]; !exists {
				ok := entity_set(&ctx.entities, data.player.entity, data.player_entity)
				assert(ok)
			}

			ctx.players[data.id] = data.player

		}
	}

	when STEAM {
		steam.init(&ctx.steam)
	}

	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		elapsed_logic_time += delta_time
		elapsed_net_time += delta_time

		update_input(&ctx, LOGIC_TICK_RATE)

		for elapsed_net_time >= NET_TICK_RATE {
			elapsed_net_time -= NET_TICK_RATE
			when STEAM {
				_ = steam.update_callback(&ctx.steam, on_receive_msg)
				update_network_steam(&ctx)
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

	game_deinit(&ctx)
	when STEAM {
		steam.deinit(&ctx.steam)
	}
}

update_network_steam :: proc(ctx: ^CultCtx) {
	for ctx.steam.event_queue.len > 0 {
		event := queue.pop_front(&ctx.steam.event_queue)
		log.debug(event)
		switch event.type {
		case .ConnectingToHost:
			ctx.scene = .Loading
		case .Created:
			ctx.flags += {.Server}
			game_init(ctx)
		case .ConnectedToHost:
			game_init(ctx)
		case .PeerDisconnected:
		case .PeerConnected:
			ctx.player_count += 1
			ctx.players[PlayerID(event.id)] = {
				entity = entity_add(&ctx.entities, PLAYER_ENTITY),
			}
		case .DisconnectedFormHost:
			game_deinit(ctx)
		}
	}

	if ctx.scene != .Game do return
	if .Server in ctx.flags {
		// TODO(Abdul): Write Events to Clients
		for i, p in ctx.players {
			steam.write(
				&ctx.steam,
				&NetData{i, p, entity_get(&ctx.entities, p.entity)^},
				size_of(NetData),
			)

		}
	}

	// TODO(Abdul): Write Inputs to Host
	if .Server not_in ctx.flags {
		player := ctx.players[ctx.player_id]
		steam.write(
			&ctx.steam,
			&NetData{ctx.player_id, player, entity_get(&ctx.entities, player.entity)^},
			size_of(NetData),
		)
	}
}


update_input :: proc(ctx: ^CultCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	input: ActionToggles

	input = rl.IsKeyDown(ctx.keymap[.Up]) ? input + {.Up} : input - {.Up}
	input = rl.IsKeyDown(ctx.keymap[.Down]) ? input + {.Down} : input - {.Down}
	input = rl.IsKeyDown(ctx.keymap[.Left]) ? input + {.Left} : input - {.Left}
	input = rl.IsKeyDown(ctx.keymap[.Right]) ? input + {.Right} : input - {.Right}

	player := ctx.players[ctx.player_id]
	player.input_down = input
	ctx.players[ctx.player_id] = player

	if rl.IsKeyPressed(ctx.keymap[.DebugCross]) {
		if .DebugCross in ctx.flags {
			ctx.flags -= {.DebugCross}
		} else {
			ctx.flags += {.DebugCross}
		}
	}

	if rl.IsKeyPressed(ctx.keymap[.Quit]) {
		game_deinit(ctx)
		steam.disconnect(&ctx.steam)
	}
}

update_logic :: proc(ctx: ^CultCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	// for &entity in ctx.entities.list {
	for _, player in ctx.players {
		// if .Controlabe in player.entity.flags { 	// movement ctl
		input: [2]f32

		input_down := player.input_down
		if .Up in input_down do input.y -= 1
		if .Down in input_down do input.y += 1
		if .Right in input_down do input.x += 1
		if .Left in input_down do input.x -= 1

		if input.x != 0 || input.y != 0 {
			dir := linalg.normalize(input)
			entity := entity_get(&ctx.entities, player.entity)
			entity.pos += dir * entity.speed * delta_time
		}
		// }
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
			ctx.max_player_count = 1
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
	for _, p in ctx.players {
		entity := entity_get(&ctx.entities, p.entity)
		if .Camera in entity.flags {
			ctx.cameras[0].target = entity.pos + (entity.size / 2)
		}
	}


	{ 	// Render world
		rl.BeginMode2D(ctx.cameras[0])
		defer rl.EndMode2D()

		rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)

		entity_iter := xar.iterator(&ctx.entities.list)
		i := 0
		for entity in xar.iterate_by_ptr(&entity_iter) {
			defer i += 1
			cstr := fmt.ctprintf("%v:%v", i, entity.generation)
			rl.DrawText(cstr, i32(entity.pos.x), i32(entity.pos.y - entity.size.y), 32, rl.BLACK)
			rl.DrawRectanglePro(
				rl.Rectangle{entity.pos.x, entity.pos.y, entity.size.x, entity.size.y},
				[2]f32{},
				0,
				rl.RED,
			)
		}
	}
}

game_init :: proc(ctx: ^CultCtx, allocator := context.allocator) {
	ctx.scene = .Game
	ctx.max_player_count = ctx.steam.max_lobby_size
	assert(ctx.steam.steam_id != 0)
	log.debug(ctx.steam.steam_id)
	ctx.player_id = PlayerID(ctx.steam.steam_id)
	ctx.player_count = ctx.steam.lobby_size
	assert(ctx.max_player_count != 0)
	ctx.players = make(map[PlayerID]Player, ctx.max_player_count)

	log.warn("game init")

	err := vmem.arena_init_growing(&ctx.entities.arena)
	ensure(err == nil)
	entities_alloc := vmem.arena_allocator(&ctx.entities.arena)
	xar.init(&ctx.entities.list, entities_alloc)

	if .Server in ctx.flags {
		assert(ctx.player_id != 0)
		assert(ctx.player_count == 1)
		entity := PLAYER_ENTITY
		entity.flags += {.Camera}
		ctx.players[ctx.player_id] = {
			entity = entity_add(&ctx.entities, entity),
		}
	} else { 	// TODO(Abdul): make it cleaner
		assert(ctx.player_count > 1)
		for i in 0 ..< ctx.player_count {
			id := steamworks.Matchmaking_GetLobbyMemberByIndex(
				ctx.steam.matchmaking,
				ctx.steam.lobby_id,
				i32(i),
			)

			assert(id != 0)

			entity := PLAYER_ENTITY
			if id == ctx.steam.steam_id {
				entity.flags += {.Camera}
			}

			ctx.players[PlayerID(id)] = {
				entity = entity_add(&ctx.entities, entity),
			}

		}
	}

	log.debug(ctx.players)
}

game_deinit :: proc(ctx: ^CultCtx) {
	ctx.scene = .MainMenu
	ctx.flags = {}
	xar.destroy(&ctx.entities.list)
	vmem.arena_destroy(&ctx.entities.arena)
}
