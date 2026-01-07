package main

import steam "./steamworks/"
import "core:c"
import "core:log"


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

    steam.NetworkingSockets_RunCallbacks()

	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)
	steam.ManualDispatch_Init()

	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
	steam.NetworkingUtils_SetGlobalConfigValueInt32(ctx.network_util, .IP_AllowWithoutAuth, 1)
	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)

}

steam_destroy :: proc() {
	steam.Shutdown()
}
