package main

import steam "./steamworks/"
import "core:c"
import "core:log"
import vmem "core:mem/virtual"
import rl "vendor:raylib"


steam_debug_text_hook :: proc "c" (severity: c.int, debugText: cstring) {
	// if you're running in the debugger, only warnings (nSeverity >= 1) will be sent
	// if you add -debug_steamworksapi to the command-line, a lot of extra informational messages will also be sent
	context = g_ctx
	log.info(string(debugText))

	if severity >= 1 {
		// runtime.debug_trap()
		panic("steam err")
	}
}


steam_networtk_debug_to_log :: proc "c" (
	net_level: steam.ESteamNetworkingSocketsDebugOutputType,
	msg: cstring,
) {
	context = g_ctx

	level: log.Level
	switch net_level {
	case .Debug:
		level = .Debug
	case .Msg, .Verbose:
		level = .Info
	case .Warning, .Important:
		level = .Warning
	case .Error:
		level = .Error
	case .Bug:
		level = .Fatal
	case .None, .Everything, ._Force32Bit:
		fallthrough
	case:
		log.panicf("unexpected log level %v", net_level)
	}


	context.logger.procedure(context.logger.data, level, string(msg), context.logger.options)
}

SteamCtx :: struct {
	user:            ^steam.IUser,
	network_util:    ^steam.INetworkingUtils,
	network:         ^steam.INetworking,
	network_message: ^steam.INetworkingMessages,
	client:          ^steam.IClient,
	matchmaking:     ^steam.IMatchmaking,
}
// when STEAM {
// } else {
// 	SteamCtx :: struct {}
// }


steam_init :: proc(ctx: ^SteamCtx) {
	if steam.RestartAppIfNecessary(steam.uAppIdInvalid) {
		log.info("start through steam")
		return
	}

	err_msg: steam.SteamErrMsg
	if err := steam.InitFlat(&err_msg); err != .OK {
		log.panicf(
			`steam.InitFlat failed with code '%v' and message "%v"
            Steam Init failed. Make sure Steam is running.`,
			err,
			transmute(cstring)&err_msg[0],
		)
	}

	ctx.client = steam.Client()
	ctx.network = steam.Networking()
	ctx.network_message = steam.NetworkingMessages_SteamAPI()
	ctx.network_util = steam.NetworkingUtils_SteamAPI()
	ctx.matchmaking = steam.Matchmaking()
	ctx.user = steam.User()


	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)

	// steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)

	steam.ManualDispatch_Init()

}

steam_callback_upadate :: proc(ctx: ^CultCtx, arena: ^vmem.Arena) {
	context.allocator = vmem.arena_allocator(arena)
	temp := vmem.arena_temp_begin(arena)
	defer vmem.arena_temp_end(temp)

	temp_mem := make([dynamic]byte)
	h_pipe := steam.GetHSteamPipe()
	steam.ManualDispatch_RunFrame(h_pipe)

	callback: steam.CallbackMsg
	for (steam.ManualDispatch_GetNextCallback(h_pipe, &callback)) {
		defer steam.ManualDispatch_FreeLastCallback(h_pipe)

		if callback.iCallback == .SteamAPICallCompleted {
			completed_callback := cast(^steam.SteamAPICallCompleted)callback.pubParam
			param := make([dynamic]byte, callback.cubParam)
			failed: bool
			ok := steam.ManualDispatch_GetAPICallResult(
				h_pipe,
				completed_callback.hAsyncCall,
				raw_data(param[:]),
				i32(completed_callback.cubParam),
				completed_callback.iCallback,
				&failed,
			)
			if failed || !ok do continue
			steam_callback_complete_handle(ctx, completed_callback, (&param[0]))


		}

		steam_callback_handler(ctx, &callback)

	}

}

steam_destroy :: proc() {
	steam.Shutdown()
	// steam.SteamGameServer_Shutdown()
}

steam_callback_complete_handle :: proc(
	ctx: ^CultCtx,
	callback: ^steam.SteamAPICallCompleted,
	param: rawptr,
) {
	#partial switch callback.iCallback {
	case .LobbyEnter:
		data := (^steam.LobbyEnter)(param)
	case .LobbyDataUpdate:
	case .LobbyCreated:
		data := (^steam.LobbyCreated)(param)
	}
	log.info("Completed Callback:", callback.iCallback)
}


steam_callback_handler :: proc(ctx: ^CultCtx, callback: ^steam.CallbackMsg) {
	#partial switch callback.iCallback {
	case .GameRichPresenceJoinRequested:
	case .LobbyChatUpdate:
		data := (^steam.LobbyChatUpdate)(callback.pubParam)
		log.info(data)
	case .LobbyEnter:
	case .GameLobbyJoinRequested:
		data := (^steam.GameLobbyJoinRequested)(callback.pubParam)
		_ = steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
	}
	log.info("Callback:", callback.iCallback)
}
