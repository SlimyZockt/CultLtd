package main

import "base:runtime"
import "core:c"
import "core:flags"
import "core:log"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import old_os "core:os"
import os "core:os/os2"
import "core:testing"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

import ase "./aseprite"
import vmem "core:mem/virtual"

LOGIC_FPS :: 60
LOGIC_TICK_RATE :: 1.0 / LOGIC_FPS

LOG_PATH :: "berry.logs"


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

Entity :: struct {
	flags:     EntityFlags,
	speed:     f32,
	using pos: [2]f32,
	size:      [2]f32,
	id:        u64,
	// vel:       [2]f32,
}

CultCtxFlagBits :: enum u32 {
	DebugCross,
}

CultCtxFlags :: bit_set[CultCtxFlagBits;u32]

CultCtx :: struct {
	flags:       CultCtxFlags,
	render_size: [2]f32,
	cameras:     []rl.Camera2D,
	entities:    [dynamic]Entity,
}

// Global
g_berry_debug := ODIN_DEBUG
g_ctx: runtime.Context
g_arena: vmem.Arena

main :: proc() {
	g_ctx = context
	if g_berry_debug {
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

		rl.SetTraceLogLevel(.ALL)
		rl.SetTraceLogCallback(rl_trace_to_log)
		ase.genereate_png_from_ase("aseprite", "./assets/")
	}
	context = g_ctx


	rl.SetConfigFlags({.FULLSCREEN_MODE, .BORDERLESS_WINDOWED_MODE})
	rl.InitWindow(0, 0, "CultLtd.")
	defer rl.CloseWindow()

	arena_err := vmem.arena_init_growing(&g_arena)
	ensure(arena_err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)

	monitor_id: i32
	monitor_count := rl.GetMonitorCount()
	if monitor_count > 1 {
		for i in 0 ..= monitor_count {
			if i + 1 > monitor_count do break
			monitor_id = rl.GetMonitorHeight(monitor_id) > rl.GetMonitorHeight(i + 1) ? i : i + 1
		}
		rl.SetWindowMonitor(monitor_id)
	}


	ctx: CultCtx
	ctx.render_size = {f32(rl.GetRenderWidth()), f32(rl.GetRenderHeight())}
	ctx.flags = {}
	ctx.entities = make([dynamic]Entity, 0, 128)

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

	// rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		delta_time := rl.GetFrameTime()
		elapsed_time += delta_time

		for elapsed_time >= LOGIC_TICK_RATE {
			elapsed_time -= LOGIC_TICK_RATE

			logic_upadate(LOGIC_TICK_RATE, &ctx)
		}


		{ 	// Render
			rl.BeginDrawing()
			rl.ClearBackground(rl.WHITE)
			defer rl.EndDrawing()

			render_upadate(delta_time, &ctx)

			rl.DrawFPS(0, 0)
		}
	}
}


logic_upadate :: proc(delta_time: f32, ctx: ^CultCtx) {


	for &entity in ctx.entities {
		if .Controlabe in entity.flags { 	// movement ctl

			input: [2]f32
			if rl.IsKeyDown(.W) do input.y -= 1
			if rl.IsKeyDown(.S) do input.y += 1
			if rl.IsKeyDown(.D) do input.x += 1
			if rl.IsKeyDown(.A) do input.x -= 1

			if input.x != 0 || input.y != 0 {
				dir := linalg.normalize(input)
				entity.pos += dir * entity.speed * LOGIC_TICK_RATE
			}
		}
	}
}


render_upadate :: proc(delta_time: f32, ctx: ^CultCtx) {
	camera_folow_entiy :: proc(player: ^Entity, camera: ^rl.Camera2D) {
		camera.target = player.pos + (player.size / 2)

		rl.BeginMode2D(camera^)
		defer rl.EndMode2D()

		rl.DrawRectangle(0, 0, 64, 64, rl.GRAY)

		rl.DrawRectanglePro(
			rl.Rectangle{player.pos.x, player.pos.y, player.size.x, player.size.y},
			[2]f32{},
			0,
			rl.RED,
		)
	}

	for &entity in ctx.entities {
		if .Camera in entity.flags {
			camera_folow_entiy(&entity, &ctx.cameras[0])
		}
	}

	if rl.IsKeyPressed(.F2) {
		if .DebugCross in ctx.flags {
			ctx.flags -= {.DebugCross}
		} else {
			ctx.flags += {.DebugCross}
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
