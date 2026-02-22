// Sacrifice other world beings to grow your factory
package game

import "base:runtime"
import "core:c"
import "core:container/queue"
import "core:container/xar"
import "core:log"
import vmem "core:mem/virtual"
import os "core:os"
import "core:prof/spall"
import "core:sync"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import ase "../aseprite"
import "../steam"


EntityFlagBits :: enum u32 {
	Controlabe,
	Sync,
	Alive,
	Destroy,
	Physics,
	TTL,
}
EntityFlags :: bit_set[EntityFlagBits;u32]

TextureId :: distinct u64

EntityHandle :: struct {
	id:         u64,
	generation: u64,
}

INVALID_PLAYER_ID :: PlayerId(0)
EntitySyncData :: struct {
	speed:          f32,
	flags:          EntityFlags,
	angle:          f32,
	friction:       f32,
	direction:      [2]f32,
	using position: [2]f32,
	velocity:       [2]f32,
	size:           [2]f32,
	network_id:     EntityNetworkId,
	ttl:            Seconds,
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

Action :: enum u8 {
	DebugCross,
	Up,
	Down,
	Left,
	Right,
	Interact,
	Quit,
	PrimaryAction,
	SecondaryAction,
	Dash,
}

Scenes :: enum u32 {
	MainMenu = 0,
	Loading  = 1,
	Game     = 2,
}

ActionsDown :: bit_set[Action;u32]
ActionsPressed :: bit_set[Action;u32]
Seconds :: distinct f32
PlayerId :: distinct u64

PlayerSyncData :: struct {
	input_down:            ActionsDown,
	input_pressed:         ActionsPressed,
	mouse_position_screen: [2]f32,
	mouse_position_world:  [2]f32,
}

Player :: struct {
	using network_shared_data: PlayerSyncData,
	entity:                    EntityHandle,
	input_pressed_queue:       queue.Queue(ActionsDown),
	// ZZZ(Abdul)
}

RenderCtx :: struct {
	scene:       Scenes,
	render_size: [2]f32,
	camera:      rl.Camera2D,
	textures:    [dynamic]rl.Texture,
}

Inputs :: union #no_nil {
	rl.KeyboardKey,
	rl.MouseButton,
}

EntityNetworkId :: distinct u64
CultCtx :: struct {
	player_count:                u16,
	max_player_count:            u16,
	elapsed_logic_time:          f32,
	elapsed_net_time:            f32,
	flags:                       CultCtxFlags,
	player_id:                   PlayerId,
	network_next_id_server:      EntityNetworkId,
	using render_ctx:            RenderCtx,
	entities:                    EntityList,
	keymap:                      [Action]Inputs,
	players:                     map[PlayerId]Player,
	network_id_to_handle_client: map[EntityNetworkId]EntityHandle,
	pending_player_assignment:   Maybe(EntityNetworkId),
	steam:                       steam.SteamCtx,
}

NetworkDataType :: enum u8 {
	ServerSnapshot,
	ClientInput,
	PlayerAssignment,
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
	id:           PlayerId,
	using player: PlayerSyncData,
}

NetworkPlayerAssignment :: struct #packed {
	using header:      NetworkMsgHeader,
	target_player_id:  PlayerId,
	entity_network_id: EntityNetworkId,
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
	net = {
		speed = 500,
		size = {32, 64},
		flags = {.Controlabe, .Sync, .Alive, .Physics},
		friction = 1000,
	},
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

g_buffer_backing: []u8
g_game_ctx: CultCtx

@(export)
game_init_engine :: proc() {
	g_ctx = context
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
}

@(export)
game_init :: proc() {
	{ 	// Profiler
		g_spall_ctx = spall.context_create("trace.spall")

		g_buffer_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)

		spall_buffer = spall.buffer_create(g_buffer_backing, u32(sync.current_thread_id()))
	}

	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	// allocator := vmem.arena_allocator(&g_arena)

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
	g_game_ctx = CultCtx {
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
			.Dash = .LEFT_SHIFT,
			.PrimaryAction = rl.MouseButton.LEFT,
			.SecondaryAction = rl.MouseButton.RIGHT,
		},
	}


	monitor_id: i32
	monitor_count := rl.GetMonitorCount()
	g_game_ctx.render_size.y = f32(rl.GetMonitorHeight(0))
	for i in 0 ..< monitor_count {
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

	g_game_ctx.camera = {
		offset = g_game_ctx.render_size / 2,
		zoom   = 1,
	}

	log.debug(g_game_ctx.render_size)

	when PLATFORM == .STEAM {
		steam.init(&g_game_ctx.steam)
	}
}

@(export)
game_update :: proc() {
	delta_time := rl.GetFrameTime()
	g_game_ctx.elapsed_logic_time += delta_time
	g_game_ctx.elapsed_net_time += delta_time

	update_input(&g_game_ctx, LOGIC_TICK_RATE)

	when PLATFORM == .STEAM {
		for g_game_ctx.elapsed_net_time >= NET_TICK_RATE {
			g_game_ctx.elapsed_net_time -= NET_TICK_RATE
			_ = steam.update_callback(&g_game_ctx.steam)
			update_network_steam(&g_game_ctx)
		}
	}

	for g_game_ctx.elapsed_logic_time >= LOGIC_TICK_RATE {
		g_game_ctx.elapsed_logic_time -= LOGIC_TICK_RATE
		update_logic(&g_game_ctx, LOGIC_TICK_RATE)
	}

	{ 	// Render
		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)
		defer rl.EndDrawing()

		draw(&g_game_ctx, delta_time)

		rl.DrawFPS(0, 0)
	}
	spall.SCOPED_EVENT(&g_spall_ctx, &spall_buffer, #procedure)
}

@(export)
game_should_run :: proc() -> bool {
	return !rl.WindowShouldClose() //TODO(abdul): replace with a proper
}

@(export)
game_shutdown :: proc() {
	{ 	// Profiler
		spall.context_destroy(&g_spall_ctx)
		delete(g_buffer_backing)
		spall.buffer_destroy(&g_spall_ctx, &spall_buffer)
	}
	when PLATFORM == .STEAM {
		steam.deinit(&g_game_ctx.steam)
	}
	vmem.arena_destroy(&g_arena)
}

@(export)
game_shutdown_engine :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return &g_game_ctx
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(CultCtx)
}

@(export)
game_hot_reloaded :: proc(memory: rawptr) {
	g_game_ctx = (^CultCtx)(memory)^
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

game_enter :: proc(ctx: ^CultCtx, allocator: runtime.Allocator, is_multiplayer := false) {
	ctx.scene = .Game

	if is_multiplayer && PLATFORM == .STEAM {
		assert(ctx.steam.max_lobby_size > 0)
		assert(ctx.steam.lobby_size > 0)
		ctx.player_id = PlayerId(ctx.steam.steam_id)
		ctx.max_player_count = ctx.steam.max_lobby_size
		ctx.player_count = ctx.steam.lobby_size
	} else if !is_multiplayer && PLATFORM == .STEAM {
		ctx.flags += {.Server}
		ctx.player_id = PlayerId(ctx.steam.steam_id)
		ctx.max_player_count = 1
		ctx.player_count = 1
	} else {
		log.panic("Current Platform is not Supported")
	}
	assert(ctx.player_id != INVALID_PLAYER_ID)

	assert(ctx.max_player_count > 0)
	assert(ctx.player_count > 0)
	ctx.players = make(map[PlayerId]Player, ctx.max_player_count, allocator)

	err := vmem.arena_init_growing(&ctx.entities.arena)
	ensure(err == nil)
	entities_alloc := vmem.arena_allocator(&ctx.entities.arena)
	xar.init(&ctx.entities.list, entities_alloc)
	if .Server in ctx.flags {
		assert(ctx.player_id != 0)
		assert(ctx.player_count == 1)
		entity := PLAYER_ENTITY
		ctx.players[ctx.player_id] = {
			entity = entity_add_sync_server(ctx, entity),
		}
		log.debug("Game enter")
	} else {
		ctx.network_id_to_handle_client = make(map[EntityNetworkId]EntityHandle, 100, allocator)
	}


	log.warn("Game was initilazes")
}

game_exit :: proc(ctx: ^CultCtx, allocator := context.allocator) {
	ctx.scene = .MainMenu
	ctx.flags = {}
	xar.destroy(&ctx.entities.list)
	// delete(ctx.players)
	// delete(ctx.network_id_to_handle_client)
	free_all(allocator)
	vmem.arena_destroy(&ctx.entities.arena)
}
