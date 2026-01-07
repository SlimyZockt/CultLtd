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

	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
	steam.NetworkingUtils_SetGlobalConfigValueInt32(ctx.network_util, .IP_AllowWithoutAuth, 1)
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
			call_completed := transmute(^steam.SteamAPICallCompleted)callback.pubParam
			param := make([dynamic]byte, callback.cubParam)
			failed: bool
			if steam.ManualDispatch_GetAPICallResult(
				h_pipe,
				call_completed.hAsyncCall,
				raw_data(param[:]),
				callback.cubParam,
				call_completed.iCallback,
				&failed,
			) {
				log.info(call_completed.iCallback)
				#partial switch call_completed.iCallback {
				case .GameRichPresenceJoinRequested:
					data := (^steam.GameLobbyJoinRequested)(&param[0])
					steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
					log.debug("Joined ")
				case .LobbyChatUpdate:
					data := (^steam.LobbyChatUpdate)(&param[0])
					log.info("Entered:", data.ulSteamIDLobby)
				case .LobbyEnter:
					data := (^steam.LobbyEnter)(&param[0])
					log.info("Entered Lobby:", data.ulSteamIDLobby)
				case .GameLobbyJoinRequested:
					data := (^steam.GameLobbyJoinRequested)(&param[0])
					steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
					log.debug("Joined ")
				case .LobbyCreated:
					data := (^steam.LobbyCreated)(&param[0])
					// ok := steam.Matchmaking_SetLobbyData(
					// 	ctx.matchmaking,
					// 	data.ulSteamIDLobby,
					// 	"Test",
					// 	"Test",
					// )
					// log.debug(ok)
					// ok = steam.Matchmaking_SetLobbyJoinable(
					// 	ctx.matchmaking,
					// 	data.ulSteamIDLobby,
					// 	true,
					// )

					log.info(data)
				}
			}

			// log.info(call_completed.iCallback)
			// }

		}

	}

}

steam_destroy :: proc() {
	steam.Shutdown()
}
