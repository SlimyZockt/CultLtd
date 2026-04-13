// Sacrifice other world beings to grow your factory
package game

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:container/queue"
import "core:container/xar"
import "core:log"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:math/rand"
import vmem "core:mem/virtual"
import os "core:os"
import "core:prof/spall"
import "core:sync"
import "core:time"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import ase_cli "../aseprite"
import "../steam"

EntityFlagBits :: enum u32 {
	Controlabe,
	Sync,
	Alive,
	Destroy,
	DestroyOnVelocityStop,
	Velocity,
	TTL,
	Moving,
}

EntityFlags :: bit_set[EntityFlagBits;u32]

TextureId :: enum u64 {
	None = 0,
	Player,
	Bullet,
}


Handle :: struct {
	id:         u64,
	generation: u64,
}

EntityHandle :: distinct Handle
ItemHandle :: distinct Handle

ItemNetData :: struct {
	grid_position: Vec2,
	texture_id:    TextureId,
	quantity:      u16,
	max_quantity:  u16,
}

Item :: struct {
	generation:  u64,
	ui_position: Vec2,
	using net:   ItemNetData,
}

INVALID_PLAYER_ID :: PlayerId(0)

Vec2 :: [2]f32
Vec3 :: [3]f32
Color :: rl.Color

EntityNetData :: struct {
	flags:          EntityFlags,
	speed:          f32,
	// angle:          f32,
	friction:       f32,
	ttl_in_s:       f32,
	tint:           Color,
	direction:      Vec2,
	using position: Vec2,
	velocity:       Vec2,
	size:           Vec2,
	network_id:     EntityNetworkId,
	texture_id:     TextureId,
}

Entity :: struct {
	generation:        u64,
	texture:           rl.Texture,
	using net:         EntityNetData,
	NextFreeEntityIdx: Maybe(u64),
}

EntityList :: struct {
	list:          xar.Array(Entity, 4),
	FreeEntityIdx: Maybe(u64),
	arena:         vmem.Arena,
}

CultCtxFlagBits :: enum u32 {
	Host,
	Multiplayer,
	Client,
}

CultCtxFlags :: bit_set[CultCtxFlagBits;u32]

Action :: enum u8 {
	DebugMenu,
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

Actions :: bit_set[Action;u32]
Seconds :: distinct f32
PlayerId :: distinct u64

PlayerStateBits :: enum u16 {
	IsDashing,
}

PlayerState :: bit_set[PlayerStateBits;u16]
CombatMode :: enum u16 {
	Shmup,
	Runes,
	Cast,
}

PlayerSyncData :: struct {
	state:                         PlayerState,
	input_down:                    Actions,
	input_pressed:                 Actions,
	input_toggled:                 Actions,
	mouse_screen_position:         Vec2,
	mouse_virtual_screen_position: Vec2,
	hold_item:                     ItemHandle,
	combat_mode:                   CombatMode,

	// mouse_position_world:          Vec2,
}

Player :: struct {
	using network_shared_data: PlayerSyncData,
	entity:                    EntityHandle,
	input_pressed_queue:       queue.Queue(Actions),
	// ZZZ(Abdul)
}


CHUNK_SIZE :: 100

WorldTileFlagBits :: enum u32 {
	Infested,
}
WorldTileFlags :: bit_set[WorldTileFlagBits;u32]

Biome :: enum u32 {
	OCEAN,
	PLAINS,
	DESSERT,
	SNOW,
	FORREST,
	SPECIAL,
}

WorldTile :: struct {
	flags:     WorldTileFlags,
	biome:     Biome,
	layers:    [2]TextureId,
	using pos: Vec2,
}

Inputs :: union #no_nil {
	rl.KeyboardKey,
	rl.MouseButton,
}

EntityNetworkId :: distinct u64

// WORLD_SIZE :: 10_000 // TODO: change this
WORLD_SIZE :: CHUNK_SIZE
WORLD_TILE_COUNT :: WORLD_SIZE * WORLD_SIZE
#assert(WORLD_TILE_COUNT < bits.U32_MAX)
ASSET_PATH :: "../assets/debug/"

DebugOptionBits :: enum u16 {
	Cross,
	LineToMouse,
	ShowEntityHandle,
	Grid,
}

DebugOptions :: bit_set[DebugOptionBits;u16]


GameCtx :: struct {
	player_count:                u16,
	max_player_count:            u16,
	debug_options:               DebugOptions,
	elapsed_logic_time:          f32,
	elapsed_net_time:            f32,
	// elapsed_time:                f32,
	current_frame:               u32,
	seed:                        i64,
	flags:                       CultCtxFlags,
	player_id:                   PlayerId,
	network_next_id_server:      EntityNetworkId,
	entities:                    EntityList,
	keymap:                      [Action]Inputs,
	players:                     map[PlayerId]Player,
	network_id_to_handle_client: map[EntityNetworkId]EntityHandle,
	// @(rodata)
	pending_player_assignment:   Maybe(EntityNetworkId),
	steam:                       steam.SteamCtx,
	scene:                       Scenes,
	render_rect:                 rl.Rectangle,
	render_scale:                f32,
	window_size:                 Vec2,
	camera:                      rl.Camera2D,
	textures:                    [TextureId]rl.Texture,
	world_texture:               rl.Texture2D,
	render_texture:              rl.RenderTexture2D,
	chunk:                       [CHUNK_SIZE * CHUNK_SIZE]WorldTile,
}

NetworkDataType :: enum u8 {
	ServerSnapshot,
	ClientInput,
	PlayerAssignment,
}

NetworkMsgHeader :: struct #packed {
	type: NetworkDataType,
}

MAX_ENTITY_SYNC_COUNT :: u64(1000 / size_of(EntityNetData))
#assert(MAX_ENTITY_SYNC_COUNT > 0)

NetworkServerSnapshot :: struct #packed {
	using header: NetworkMsgHeader,
	entity_count: u64,
	entities:     [MAX_ENTITY_SYNC_COUNT]EntityNetData,
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

PLAYER_ENTITY :: Entity {
	net = {
		speed = 220,
		size = {16, 16},
		flags = {.Controlabe, .Sync, .Alive, .Velocity},
		friction = 2000,
		texture_id = .Player,
		tint = 0xff,
	},
	// texture_id = .Player,
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

	allocator := vmem.arena_allocator(temp.arena)
	buf := make([]byte, 4096, allocator)
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
g_game_ctx: GameCtx

@(export)
game_init_window :: proc() {
	g_ctx = context
	when ODIN_DEBUG {
		rl.SetConfigFlags({.BORDERLESS_WINDOWED_MODE, .WINDOW_UNDECORATED, .WINDOW_MINIMIZED})
	} else {
		rl.SetConfigFlags({.FULLSCREEN_MODE, .BORDERLESS_WINDOWED_MODE})
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(0, 0, "CultLtd.")
	rl.SetTargetFPS(300)
	rl.SetExitKey(nil)

}

ASSERT_DIR :: "debug_assets"

RENDER_WIDTH :: 320
RENDER_HEIGHT :: 180

@(export)
game_init :: proc() {
	rl.SetTraceLogCallback(rl_trace_to_log)
	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	allocator := vmem.arena_allocator(&g_arena)

	{ 	// Profiler
		g_spall_ctx = spall.context_create("trace.spall")

		g_buffer_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE, allocator)

		spall_buffer = spall.buffer_create(g_buffer_backing, u32(sync.current_thread_id()))
	}

	g_ctx = context

	if g_cult_debug {
		file, err := os.open(LOG_PATH, {.Read, .Write, .Create, .Trunc})
		ensure(err == nil)

		g_ctx.logger = log.create_multi_logger(
			log.create_file_logger(file, allocator = allocator),
			log.create_console_logger(allocator = allocator),
			allocator = allocator,
		)

		temp := vmem.arena_temp_begin(&g_arena)
		ase_cli.genereate_png_from_ase("aseprite", "./assets/", allocator)
		vmem.arena_temp_end(temp)
	}
	// rl.ShowCursor()

	context = g_ctx

	g_game_ctx = GameCtx {
		flags = {},
		scene = .MainMenu,
		player_count = 1,
		player_id = 0,
		keymap = {
			.DebugMenu = .F1,
			.Up = .W,
			.Down = .S,
			.Right = .D,
			.Left = .A,
			.Interact = .E,
			.Quit = .F12,
			.Dash = .SPACE,
			.PrimaryAction = rl.MouseButton.LEFT,
			.SecondaryAction = rl.MouseButton.RIGHT,
		},
		textures = {
			.None = {},
			.Player = rl.LoadTexture(ASSERT_DIR + "/player.png"),
			.Bullet = {},
		},
		render_texture = rl.LoadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT),
		window_size = Vec2{RENDER_WIDTH, RENDER_HEIGHT} * 3,
	}
	rl.SetTextureFilter(g_game_ctx.render_texture.texture, .POINT)

	{ 	//TODO(abdul): init Texture
		// g_game_ctx.textures = make([dynamic]rl.Texture2D, 0, 100, allocator)
	}

	rl.SetWindowSize(i32(g_game_ctx.window_size.x), i32(g_game_ctx.window_size.y))


	g_game_ctx.camera = {
		offset = Vec2{RENDER_WIDTH, RENDER_HEIGHT} / 2,
		zoom   = 1,
	}

	when PLATFORM == .STEAM {
		steam.init(&g_game_ctx.steam)
	}
}

@(export)
game_update :: proc() {
	delta_time := rl.GetFrameTime()
	g_game_ctx.elapsed_logic_time += delta_time
	g_game_ctx.elapsed_net_time += delta_time
	// g_game_ctx.elapsed_time += delta_time

	g_game_ctx.window_size = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	g_game_ctx.render_scale = min(
		g_game_ctx.window_size.x / RENDER_WIDTH,
		g_game_ctx.window_size.y / RENDER_HEIGHT,
	)
	g_game_ctx.render_rect = rl.Rectangle {
		(f32(g_game_ctx.window_size.x) - (f32(RENDER_WIDTH) * g_game_ctx.render_scale)) * .5,
		(f32(g_game_ctx.window_size.y) - (f32(RENDER_HEIGHT) * g_game_ctx.render_scale)) * .5,
		f32(RENDER_WIDTH) * g_game_ctx.render_scale,
		f32(RENDER_HEIGHT) * g_game_ctx.render_scale,
	}

	update_input(&g_game_ctx, LOGIC_TICK_RATE)

	when PLATFORM == .STEAM {
		for g_game_ctx.elapsed_net_time >= NET_TICK_RATE {
			g_game_ctx.elapsed_net_time -= NET_TICK_RATE
			steam.update_callback(&g_game_ctx.steam, update_network_steam, &g_game_ctx)
		}
	}

	for g_game_ctx.elapsed_logic_time >= LOGIC_TICK_RATE {
		g_game_ctx.elapsed_logic_time -= LOGIC_TICK_RATE
		// g_game_ctx.current_frame += 1
		update_logic(&g_game_ctx, LOGIC_TICK_RATE)

	}

	{ 	// Render
		{ 	// Render to Texture
			rl.BeginTextureMode(g_game_ctx.render_texture)
			defer rl.EndTextureMode()
			rl.ClearBackground(rl.WHITE) // Clear screen background
			draw(&g_game_ctx, delta_time)
		}


		{ 	// draw render texture
			rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK) // Clear screen background
			defer rl.EndDrawing()

			// Draw render texture to screen, properly scaled
			texture := g_game_ctx.render_texture.texture
			rl.DrawTexturePro(
				texture,
				{0, 0, f32(texture.width), f32(-texture.height)},
				g_game_ctx.render_rect,
				0,
				0,
				rl.WHITE,
			)

			rl.GuiSetStyle(
				.DEFAULT,
				i32(rl.GuiDefaultProperty.TEXT_SIZE),
				i32(math.floor(10 * g_game_ctx.render_scale)),
			)
			draw_ui(&g_game_ctx, delta_time)
			rl.DrawFPS(0, 0)
		}
	}
	spall.SCOPED_EVENT(&g_spall_ctx, &spall_buffer, #procedure)
}

@(export)
game_should_run :: proc() -> bool {
	return !rl.WindowShouldClose() //TODO(abdul): replace with a proper
}

@(export)
game_shutdown :: proc() {
	rl.SetTraceLogCallback(nil)
	rl.UnloadTexture(g_game_ctx.world_texture)
	rl.UnloadRenderTexture(g_game_ctx.render_texture)

	{ 	// Profiler
		spall.buffer_destroy(&g_spall_ctx, &spall_buffer)
		spall.context_destroy(&g_spall_ctx)
	}
	when PLATFORM == .STEAM {
		steam.deinit(&g_game_ctx.steam)
	}

	g_game_ctx = {}
	vmem.arena_destroy(&g_arena)
	// free_all(context.allocator)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return &g_game_ctx
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(GameCtx)
}

@(export)
game_hot_reloaded :: proc(memory: rawptr) {
	g_game_ctx = (^GameCtx)(memory)^
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

game_enter :: proc(ctx: ^GameCtx, arena: ^vmem.Arena, is_multiplayer := false) {
	ctx.scene = .Game
	allocator := vmem.arena_allocator(arena)

	if is_multiplayer && PLATFORM == .STEAM {
		assert(ctx.steam.max_lobby_size > 0)
		assert(ctx.steam.lobby_size > 0)
		ctx.player_id = PlayerId(ctx.steam.steam_id)
		ctx.max_player_count = ctx.steam.max_lobby_size
		ctx.player_count = ctx.steam.lobby_size
		ctx.flags += {.Multiplayer}
	} else if !is_multiplayer && PLATFORM == .STEAM {
		ctx.flags += {.Host}
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
	if .Host in ctx.flags {
		assert(ctx.player_id != 0)
		assert(ctx.player_count == 1)


		entity := PLAYER_ENTITY
		entity.position = WORLD_SIZE / 2
		entity_handle := entity_add_sync_server(ctx, entity)
		ctx.players[ctx.player_id] = {
			entity = entity_handle,
		}
		log.debug("Game enter")
	} else {
		ctx.network_id_to_handle_client = make(map[EntityNetworkId]EntityHandle, 100, allocator)
	}

	ctx.seed = time.tick_now()._nsec
	rand.reset(u64(ctx.seed))


	{ 	// generate world
		circle :: proc(dist: [2]$T, $radius: T) -> T where intrinsics.type_is_numeric(T),
			0 >= radius,
			1 <= radius {
			boarder := linalg.smootherstep(
				radius - (radius * 0.001),
				radius + (radius * 0.001),
				linalg.dot(dist, dist) * 4,
			)
			return boarder
		}

		hash22 :: proc(point: [2]$T) -> [2]T where intrinsics.type_is_numeric(T) {
			return linalg.fract(
				linalg.sin(
					[2]T {
						linalg.vector_dot(point, [2]T{127.1, 331.7}),
						linalg.vector_dot(point, [2]T{269.5, 183.3}),
					},
				) *
				43758.5453,
			)
		}

		poisson_disk_sample_square_2D :: proc(
			min_distance: u8,
			$max_tries_per_point: u8,
			$radius: u64,
			$size: u64,
			arena: ^runtime.Arena,
		) -> []Vec2 {
			DIMONSIONS :: 2
			CELL_SIZE :: radius / intrinsics.sqrt(2)

			alloc := vmem.arena_allocator(arena)

			points := make_dynamic_array([dynamic]Vec2, (size * size) / 10, alloc)
			points[0] = Vec2{rand.float32(), rand.float32()}
			append(&points, Vec2{1, 0})

			for {
				points
			}


			return points[:]
		}

		uv_to_color :: proc(uv: Vec2) -> rl.Color {
			return {u8(uv.x * 255), u8(uv.y * 255), 0, 255}
		}

		player := ctx.players[ctx.player_id]
		player_entity, _ := entity_get(&ctx.entities, player.entity)
		real_pos := linalg.round(player_entity.position)
		// real_pos := [2]f64{f64(t.x), f64(t.y)}

		tmp := vmem.arena_temp_begin(arena)
		defer vmem.arena_temp_end(tmp)

		// TODO: Change to World
		img_data := new([WORLD_SIZE * WORLD_SIZE][3]u8, allocator)

		img := rl.Image {
			format  = .UNCOMPRESSED_R8G8B8,
			data    = img_data,
			height  = WORLD_SIZE,
			width   = WORLD_SIZE,
			mipmaps = 1,
		}

		// rand.reset(ctx.seed)
		rand_offset := Vec2{rand.float32(), rand.float32()}

		// SEGMENT_COUNT :: (WORLD_SIZE * WORLD_SIZE) / 50
		SEGMENT_DIVIDER_COUNT :: WORLD_SIZE / 10
		BIOME_DIVIDER_COUNT :: 2
		// BIMOE_COUNT :: BIOME_DIVIDER_COUNT * BIOME_DIVIDER_COUNT
		for world_y in 0 ..< f32(WORLD_SIZE) {
			for world_x in 0 ..< f32(WORLD_SIZE) {
				pos := Vec2{world_x, world_y}
				i := int(world_x + (world_y * WORLD_SIZE))

				ctx.chunk[i].pos = real_pos + pos
				WORLD_CENTER :: WORLD_SIZE / 2

				uv := pos / WORLD_SIZE
				segment_uv := uv * SEGMENT_DIVIDER_COUNT
				grid_pos_in_segment_uv := linalg.floor(segment_uv)
				pos_in_segment := linalg.fract(segment_uv)

				min_dist_segment := f32(1)
				nearest_point_segment := Vec2{}

				for y in -1 ..= f32(1) {
					for x in -1 ..= f32(1) { 	//TODO: make it cleaner
						neighbor_tile_pos := Vec2{x, y}
						neighbor_pos_in_segment := grid_pos_in_segment_uv + neighbor_tile_pos
						anchor_point_in_segment := hash22(neighbor_pos_in_segment + rand_offset) // TODO: change to Poisson-Disc Sampling
						maybe_nearest_point_in_segment :=
							neighbor_tile_pos + anchor_point_in_segment

						diff := maybe_nearest_point_in_segment - pos_in_segment
						dist := linalg.length(diff)
						if dist < min_dist_segment {
							min_dist_segment = dist
							nearest_point_segment =
								maybe_nearest_point_in_segment + grid_pos_in_segment_uv
						}
					}
				}

				point_segment := nearest_point_segment / SEGMENT_DIVIDER_COUNT // revert uv space
				dist := linalg.distance(point_segment, Vec2{.5, .5})
				assert(0.0 <= dist && dist <= 1.0)

				rl_color := rl.BLACK
				color := nearest_point_segment * 255
				dist = 1 - dist
				switch {
				case dist < .6:
					ctx.chunk[i].biome = .OCEAN
					rl_color = rl.BLUE
				case dist < .69:
					ctx.chunk[i].biome = .DESSERT
					rl_color = rl.YELLOW
				case dist < .92:
					rl_color = rl.Color{u8(color.x), u8(color.y), 0, 255} //TODO: DEALT WITH BIOMES
				case dist < 1:
					ctx.chunk[i].biome = .SNOW
					rl_color = rl.LIGHTGRAY
				case:
				}

				rl.ImageDrawPixel(&img, i32(world_x), i32(world_y), rl_color)
				// rl.ImageDrawRectangleLines(&img, i32(world_x), i32(world_y))
			}
		}

		ctx.world_texture = rl.LoadTextureFromImage(img)
	}

	log.warn("Game was initilazes")
}

game_exit :: proc(ctx: ^GameCtx, allocator := context.allocator) {
	ctx.scene = .MainMenu
	ctx.flags = {}
	xar.destroy(&ctx.entities.list)
	vmem.arena_destroy(&g_arena)
	vmem.arena_destroy(&ctx.entities.arena)
}

entity_add_sync_server :: proc(ctx: ^GameCtx, entity: Entity) -> EntityHandle {
	entity := entity
	assert(.Sync in entity.flags)
	assert(.Host in ctx.flags)
	entity.network_id = ctx.network_next_id_server
	ctx.network_next_id_server += 1
	// entity.owner_id =
	return entity_add(&ctx.entities, entity)
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

entity_delete_sync_server :: proc(ctx: ^GameCtx, entity_handle: EntityHandle) {
	entity, ok := entity_get(&ctx.entities, entity_handle)
	assert(.Sync in entity.flags)
	if !ok {
		log.errorf("try to delete sync an not existing element %v", entity_handle)
		return
	}

	if .Multiplayer in ctx.flags {
		entity.flags += {.Destroy}
	} else {
		entity_delete(&ctx.entities, entity_handle)
	}
}

entity_delete :: proc(entities: ^EntityList, entity_handle: EntityHandle) {
	entity := xar.get_ptr(&entities.list, entity_handle.id)
	if entity.generation != entity_handle.generation {
		log.errorf("try to delete an not existing element %v", entity_handle)
		return
	}

	generation := entity.generation + 1
	entity^ = {
		generation        = generation,
		NextFreeEntityIdx = entities.FreeEntityIdx,
	}
	entities.FreeEntityIdx = entity_handle.id

	// log.infof("%v was deleted", entity_handle)
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
