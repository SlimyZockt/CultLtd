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
import os "core:os"
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
	Dead,
	Destroy,
}

EntityFlags :: bit_set[EntityFlagBits;u32]

TextureId :: distinct u64

EntityHandle :: struct {
	id:         u64,
	generation: u64,
}

EntitySyncData :: struct {
	speed:      f32,
	flags:      EntityFlags,
	using pos:  [2]f32,
	size:       [2]f32,
	network_id: EntityNetworkId,
}

Entity :: struct {
	generation:        u64,
	texture_id:        TextureId,
	using net:         EntitySyncData,
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

PlayerSyncData :: struct {
	input_down:    ActionToggles,
	input_pressed: ActionToggles,
}

Player :: struct {
	using net: PlayerSyncData,
	entity:    EntityHandle,
}


RenderCtx :: struct {
	scene:       Scenes,
	render_size: [2]f32,
	cameras:     []rl.Camera2D,
	textures:    [dynamic]rl.Texture,
}

EntityNetworkId :: distinct u64
CultCtx :: struct {
	player_count:                u16,
	max_player_count:            u16,
	flags:                       CultCtxFlags,
	player_id:                   PlayerID,
	network_next_id_server:      EntityNetworkId,
	using render_ctx:            RenderCtx,
	entities:                    EntityList,
	keymap:                      [Actions]rl.KeyboardKey,
	players:                     map[PlayerID]Player,
	network_id_to_handle_client: map[EntityNetworkId]EntityHandle,
	steam:                       steam.SteamCtx,
}

NetworkDataType :: enum u8 {
	ServerSnapshot,
	ClientInput,
}

NetworkMsgHeader :: struct #packed {
	type: NetworkDataType,
}

MAX_ENTITY_SYNC_COUNT :: u64(1000 / size_of(EntitySyncData))
#assert(MAX_ENTITY_SYNC_COUNT > 0)

NetworkServerSnapshot :: struct #packed {
	using header: NetworkMsgHeader,
	entity_count: u64,
	entities:     [MAX_ENTITY_SYNC_COUNT]EntitySyncData,
}

NetworkClientInput :: struct #packed {
	using header: NetworkMsgHeader,
	id:           PlayerID,
	using player: PlayerSyncData,
}

LOG_PATH :: "berry.logs"

Platform :: enum u8 {
	NONE  = 0,
	STEAM = 1,
	// HEADLESS
}

PLATFORM :: Platform(#config(PLATFORM, Platform.NONE))

LOGIC_TICK_RATE :: 1.0 / 60
NET_TICK_RATE :: 1.0 / 60
MAX_PLAYER_COUNT :: 8

// Global
g_cult_debug := #config(CULT_DEBUG, ODIN_DEBUG)
g_ctx: runtime.Context
g_arena: vmem.Arena
g_spall_ctx: spall.Context

PLAYER_ENTITY :: Entity {
	net = {speed = 500, size = {32, 64}, flags = {.Controlabe, .Sync}},
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

	if message == nil {
		context.logger.procedure(
			context.logger.data,
			level,
			"<nil raylib log message>",
			context.logger.options,
		)
		return
	}

	temp := vmem.arena_temp_begin(&g_arena)
	defer vmem.arena_temp_end(temp)

	arena_alloc := vmem.arena_allocator(&g_arena)
	buf := make([]byte, 4096, arena_alloc)
	log_len := stbsp.vsnprintf(raw_data(buf), i32(len(buf)), message, args)

	if log_len < 0 {
		context.logger.procedure(
			context.logger.data,
			level,
			"<raylib format error>",
			context.logger.options,
		)
		return
	}

	msg_len := min(int(log_len), len(buf) - 1)
	context.logger.procedure(
		context.logger.data,
		level,
		string(buf[:msg_len]),
		context.logger.options,
	)
}

entity_add_sync_server :: proc(ctx: ^CultCtx, entity: ^Entity) -> EntityHandle {
	log.debug(entity.flags)
	assert(.Sync in entity.flags)
	assert(.Server in ctx.flags)
	entity.network_id = ctx.network_next_id_server
	ctx.network_next_id_server += 1
	return entity_add(&ctx.entities, entity^)
}

entity_add :: proc(entities: ^EntityList, entity: Entity) -> EntityHandle {
	if idx, ok := entities.FreeEntityIdx.?; ok {
		new_entity := xar.get_ptr(&entities.list, idx)
		generation := new_entity.generation
		entities.FreeEntityIdx = new_entity.NextFreeEntityIdx

		new_entity^ = entity
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


entity_get :: proc(entities: ^EntityList, entity_handle: EntityHandle) -> (^Entity, bool) {
	@(static) entity_stub: Entity

	if int(entity_handle.id) >= entities.list.len do return &entity_stub, false
	entity := xar.get_ptr(&entities.list, entity_handle.id)
	if entity.generation != entity_handle.generation {
		log.error("Wrong generation entity")
		return &entity_stub, false
	}

	return entity, true
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
		file, err := os.open(LOG_PATH, {.Read, .Write, .Create})
		ensure(err == nil)

		g_ctx.logger = log.create_multi_logger(
			log.create_file_logger(file),
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

	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)

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

	log.debug(MAX_ENTITY_SYNC_COUNT, size_of(EntitySyncData))

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


	when PLATFORM == .STEAM {
		steam.init(&ctx.steam)
	}
	defer when PLATFORM == .STEAM {
		steam.deinit(&ctx.steam)
	}

	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		elapsed_logic_time += delta_time
		elapsed_net_time += delta_time

		update_input(&ctx, LOGIC_TICK_RATE)

		when PLATFORM == .STEAM {
			for elapsed_net_time >= NET_TICK_RATE {
				elapsed_net_time -= NET_TICK_RATE
				_ = steam.update_callback(&ctx.steam)
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
}


update_network_steam :: proc(ctx: ^CultCtx) {
	on_receive_msg :: proc(msg: ^steamworks.SteamNetworkingMessage, user_data: rawptr) {
		ctx := (^CultCtx)(user_data)
		header := (^NetworkMsgHeader)(msg.pData)

		switch header.type {
		case .ServerSnapshot:
			assert(.Server not_in ctx.flags)
			data := (^NetworkServerSnapshot)(msg.pData)
			assert(data.entity_count <= MAX_ENTITY_SYNC_COUNT)
			for i in 0 ..< min(data.entity_count, MAX_ENTITY_SYNC_COUNT) {
				entity_data := data.entities[i]

				handle, exists := ctx.network_id_to_handle_client[entity_data.network_id]
				if !exists {
					if .Destroy in entity_data.flags do continue
					new_handle := entity_add(&ctx.entities, Entity{net = entity_data})
					ctx.network_id_to_handle_client[entity_data.network_id] = new_handle
					continue
				}

				if .Destroy in entity_data.flags {
					entity_delete(&ctx.entities, handle)
					delete_key(&ctx.network_id_to_handle_client, entity_data.network_id)
					continue
				}

				entity, ok := entity_get(&ctx.entities, handle)
				if !ok {
					delete_key(&ctx.network_id_to_handle_client, entity_data.network_id)
					continue
				}

				entity.net = entity_data

				continue
			}

		case .ClientInput:
			assert(.Server in ctx.flags)
			data := (^NetworkClientInput)(msg.pData)
			player, ok := ctx.players[data.id]
			if !ok do return
			player.net = data.player
			ctx.players[data.id] = player
		}
	}

	for ctx.steam.event_queue.len > 0 {
		event := queue.pop_front(&ctx.steam.event_queue)
		log.debug(event)
		switch event.type {
		case .ConnectingToHost:
			ctx.scene = .Loading
		case .Created:
			ctx.flags += {.Server}
			game_init(ctx, true)
		case .ConnectedToHost:
			game_init(ctx, true)
		case .PeerDisconnected:
			peer_handle := ctx.players[PlayerID(event.id)].entity
			peer_entity, _ := entity_get(&ctx.entities, peer_handle)
			peer_entity.flags += {.Dead, .Destroy}
		case .PeerConnected:
			ctx.player_count += 1
			entity := PLAYER_ENTITY
			ctx.players[PlayerID(event.id)] = {
				entity = entity_add_sync_server(ctx, &entity),
			}
		case .DisconnectedFormHost:
			game_deinit(ctx)
		}
	}

	if ctx.scene != .Game do return
	steam.process_received_msg(ctx.steam, on_receive_msg, ctx)

	if .Server in ctx.flags {
		packet := NetworkServerSnapshot {
			type = .ServerSnapshot,
		}
		i := u64(0)

		iter := xar.iterator(&ctx.entities.list)
		for entity in xar.iterate_by_ptr(&iter) {
			defer i += 1
			if .Sync in entity.flags {
				packet.entities[packet.entity_count] = entity
				packet.entity_count += 1
			}

			if packet.entity_count == MAX_ENTITY_SYNC_COUNT {
				steam.write(&ctx.steam, &packet, size_of(packet))
				packet = NetworkServerSnapshot {
					type = .ServerSnapshot,
				}
			}

			if entity.flags >= {.Destroy, .Sync} {
				entity.flags -= {.Destroy, .Sync}
				entity_delete(&ctx.entities, EntityHandle{i, entity.generation})
			}
		}

		if packet.entity_count > 0 {
			steam.write(&ctx.steam, &packet, size_of(packet))
		}

		iter = xar.iterator(&ctx.entities.list)
		for entity in xar.iterate_by_ptr(&iter) {
			if entity.flags >= {.Destroy, .Sync} {
				entity.flags -= {.Destroy, .Sync}
				entity_delete(&ctx.entities, EntityHandle{i, entity.generation})
			}
		}

	}

	if .Server not_in ctx.flags {
		player := ctx.players[ctx.player_id]
		packet := NetworkClientInput {
			type   = .ClientInput,
			id     = ctx.player_id,
			player = player.net,
		}
		steam.write(&ctx.steam, &packet, size_of(packet))
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
			entity, _ := entity_get(&ctx.entities, player.entity)
			entity.pos += dir * entity.speed * delta_time
		}
		// }
	}
}

update_render :: proc(ctx: ^CultCtx, delta_time: f32) {
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

update_game_render :: proc(ctx: ^CultCtx, delta_time: f32) {
	// player := entity_get(ctx.entities, ctx.player)
	// ctx.cameras[0].target = player.pos + (player.size / 2)


	{ 	// Render UI

	}

	player, ok := ctx.players[ctx.player_id]
	if ok {
		entity, _ := entity_get(&ctx.entities, player.entity)
		if entity != nil {
			ctx.cameras[0].target = entity.pos + (entity.size / 2)
		}
	}


	{ 	// Render world
		rl.BeginMode2D(ctx.cameras[0])
		defer rl.EndMode2D()
		default_font := rl.GetFontDefault()

		rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)

		entity_iter := xar.iterator(&ctx.entities.list)
		i := 0
		for entity in xar.iterate_by_ptr(&entity_iter) {
			defer i += 1
			if .Dead in entity.flags do continue
			cstr := fmt.ctprintf("%v:%v", i, entity.generation)
			rl.DrawTextPro(
				default_font,
				cstr,
				[2]f32{entity.pos.x, entity.pos.y - entity.size.y},
				[2]f32{},
				0,
				32,
				1,
				rl.BLACK,
			)
			rl.DrawRectanglePro(
				rl.Rectangle{entity.pos.x, entity.pos.y, entity.size.x, entity.size.y},
				[2]f32{},
				0,
				rl.RED,
			)
		}
	}
}

game_init :: proc(ctx: ^CultCtx, is_multiplayer := false, allocator := context.allocator) {
	ctx.scene = .Game

	if is_multiplayer && PLATFORM == .STEAM {
		assert(ctx.steam.steam_id != 0)
		assert(ctx.steam.max_lobby_size > 0)
		assert(ctx.steam.lobby_size > 0)
		ctx.player_id = PlayerID(ctx.steam.steam_id)
		ctx.max_player_count = ctx.steam.max_lobby_size
		ctx.player_count = ctx.steam.lobby_size
	} else if !is_multiplayer && PLATFORM == .STEAM {
		ctx.flags += {.Server}
		ctx.player_id = PlayerID(ctx.steam.steam_id)
		ctx.max_player_count = 1
		ctx.player_count = 1
	} else {
		log.panic("Current Platform is not Supported")
	}

	ctx.players = make(map[PlayerID]Player, ctx.max_player_count, allocator)

	err := vmem.arena_init_growing(&ctx.entities.arena)
	ensure(err == nil)
	entities_alloc := vmem.arena_allocator(&ctx.entities.arena)
	xar.init(&ctx.entities.list, entities_alloc)
	if .Server in ctx.flags {
		assert(ctx.player_id != 0)
		assert(ctx.player_count == 1)
		entity := PLAYER_ENTITY
		entity.flags += {.Camera}
		log.warn(entity)
		ctx.players[ctx.player_id] = {
			entity = entity_add_sync_server(ctx, &entity),
		}
	} else {
		ctx.network_id_to_handle_client = make(map[EntityNetworkId]EntityHandle, 100, allocator)
	}


	log.debug(ctx.players)
	log.warn("Game was initilazes")
}

game_deinit :: proc(ctx: ^CultCtx, allocator := context.allocator) {
	ctx.scene = .MainMenu
	ctx.flags = {}
	xar.destroy(&ctx.entities.list)
	// delete(ctx.players)
	// delete(ctx.network_id_to_handle_client)
	free_all(allocator)
	vmem.arena_destroy(&ctx.entities.arena)
}
