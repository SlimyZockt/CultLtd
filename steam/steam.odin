package steam

import steam "../steamworks/"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:strings"


MAX_LOBBY_SIZE :: 8
LOBBY_DATA_KEY :: "key"
SteamCtx :: struct {
	user:            ^steam.IUser,
	network_util:    ^steam.INetworkingUtils,
	network:         ^steam.INetworking,
	network_sockets: ^steam.INetworkingSockets,
	client:          ^steam.IClient,
	matchmaking:     ^steam.IMatchmaking,
	friends:         ^steam.IFriends,
	steam_id:        steam.CSteamID,
	lobby_id:        steam.CSteamID,
	socket:          steam.HSteamListenSocket,
	poll_group:      steam.HSteamNetPollGroup,
	user_identity:   steam.SteamNetworkingIdentity,
	host_identity:   steam.SteamNetworkingIdentity,
	connection:      steam.HSteamNetConnection,
	on_lobby_enter:  proc(ctx: SteamCtx),
	on_lobby_leave:  proc(ctx: SteamCtx),
}

g_steam: SteamCtx
g_ctx: runtime.Context

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

init :: proc(ctx: ^SteamCtx) {
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
	ctx.network_sockets = steam.NetworkingSockets_SteamAPI()
	ctx.network_util = steam.NetworkingUtils_SteamAPI()
	ctx.matchmaking = steam.Matchmaking()
	ctx.user = steam.User()
	ctx.friends = steam.Friends()
	ctx.steam_id = steam.User_GetSteamID(ctx.user)
	ctx.socket = steam.HSteamListenSocket_Invalid
	ctx.connection = steam.HSteamNetConnection_Invalid

	steam.NetworkingIdentity_SetSteamID(&ctx.user_identity, ctx.steam_id)

	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)

	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)

	steam.ManualDispatch_Init()
	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)

	// init socket
	ctx.socket = steam.NetworkingSockets_CreateListenSocketP2P(ctx.network_sockets, 0, 0, nil)
	ctx.poll_group = steam.NetworkingSockets_CreatePollGroup(ctx.network_sockets)

}

upadate_callback :: proc(ctx: ^SteamCtx, arena: ^vmem.Arena) {
	temp := vmem.arena_temp_begin(arena)
	context.allocator = vmem.arena_allocator(arena)
	defer vmem.arena_temp_end(temp)

	h_pipe := steam.GetHSteamPipe()
	steam.ManualDispatch_RunFrame(h_pipe)

	callback: steam.CallbackMsg
	for (steam.ManualDispatch_GetNextCallback(h_pipe, &callback)) {
		defer steam.ManualDispatch_FreeLastCallback(h_pipe)

		if callback.iCallback == .SteamAPICallCompleted {
			completed_callback := cast(^steam.SteamAPICallCompleted)callback.pubParam
			param := make([dynamic]byte, completed_callback.cubParam)
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
			callback_complete_handle(ctx, completed_callback, (&param[0]))
			continue
		}

		callback_handler(ctx, &callback)

	}
}

destroy :: proc(ctx: SteamCtx) {
	if ctx.socket != steam.HSteamListenSocket_Invalid {
		steam.NetworkingSockets_CloseListenSocket(ctx.network_sockets, ctx.socket)
	}
	steam.Shutdown()
	// steam.SteamGameServer_Shutdown()
}

callback_complete_handle :: proc(
	ctx: ^SteamCtx,
	callback: ^steam.SteamAPICallCompleted,
	param: rawptr,
) {
	#partial switch callback.iCallback {
	case .LobbyEnter:
		data := (^steam.LobbyEnter)(param)
		log.debug(steam.EChatRoomEnterResponse(data.EChatRoomEnterResponse))
		assert(data.EChatRoomEnterResponse == u32(steam.EChatRoomEnterResponse.Success))
	case .LobbyDataUpdate:
	case .LobbyCreated:
		data := (^steam.LobbyCreated)(param)
		assert(data.eResult == .OK)
		ctx.lobby_id = data.ulSteamIDLobby
		id_str := fmt.ctprintf("%v", ctx.steam_id)
		steam.Matchmaking_SetLobbyData(ctx.matchmaking, ctx.lobby_id, LOBBY_DATA_KEY, id_str)
		log.info("Listen Sockets")
	}
	log.info("Completed Callback:", callback.iCallback)
}


callback_handler :: proc(ctx: ^SteamCtx, callback: ^steam.CallbackMsg) {
	#partial switch callback.iCallback {
	case .GameRichPresenceJoinRequested:
	case .SteamNetConnectionStatusChangedCallback:
		data := (^steam.SteamNetConnectionStatusChangedCallback)(callback.pubParam)
		// data := (^steam.SteamNetConnectionStatusChangedCallback)(param)

		is_connecting :=
			data.info.hListenSocket != 0 &&
			data.info.eState == .Connecting &&
			data.eOldState == .None

		log.infof("%v", data)
		log.infof("%b", data.info.eState)
		log.infof("%v", is_connecting)

		if is_connecting {
			res := steam.NetworkingSockets_AcceptConnection(ctx.network_sockets, data.hConn)
			assert(res == .OK)
			ctx.connection = data.hConn

			ctx.on_lobby_enter(ctx^)
		}


		is_closed :=
			data.info.hListenSocket != 0 &&
			data.eOldState == .Connected &&
			(data.info.eState == .ClosedByPeer || data.info.eState == .ProblemDetectedLocally)

		if is_closed {
			steam.NetworkingSockets_CloseConnection(ctx.network_sockets, data.hConn, 0, nil, false)
			if data.hConn == ctx.connection {
				ctx.connection = steam.HSteamNetConnection_Invalid
			}
			// ctx.socket = steam.HSteamListenSocket_Invalid
			ctx.on_lobby_leave(ctx^)
		}


	// if data.info
	case .LobbyChatUpdate:
		data := (^steam.LobbyChatUpdate)(callback.pubParam)
		log.info(data.rgfChatMemberStateChange)
		state := cast(steam.EChatMemberStateChange)(data.rgfChatMemberStateChange)
		switch state {
		case .Entered:
			// ctx.lobby
			log.infof("%v entered", data.ulSteamIDUserChanged)
		// ctx.lobby_id = data.ulSteamIDLobby
		case .Disconnected, .Left, .Kicked, .Banned:
			log.infof("%v left", data.ulSteamIDUserChanged)
		// ctx.lobby_id = 0
		}
	case .GameLobbyJoinRequested:
		// connect to peer
		data := (^steam.GameLobbyJoinRequested)(callback.pubParam)
		steam.NetworkingIdentity_SetSteamID(&ctx.host_identity, data.steamIDFriend)
		ctx.connection = steam.NetworkingSockets_ConnectP2P(
			ctx.network_sockets,
			&ctx.host_identity,
			0,
			0,
			nil,
		)
		_ = steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
		assert(!steam.NetworkingIdentity_IsInvalid(&ctx.host_identity))
		name := steam.Friends_GetFriendPersonaName(ctx.friends, data.steamIDFriend)
		log.infof("trying to connect to user %v (%v).", name, data.steamIDFriend)
	}

	log.info("Callback:", callback.iCallback)
}

host :: proc(ctx: ^SteamCtx) {
	_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, 4)
}


// connect_to_peer :: proc(ctx: ^SteamCtx) {
// 	id: steam.SteamNetworkingIdentity
// 	steam.NetworkingIdentity_SetSteamID(
// 		&id,
// 		steam.Matchmaking_GetLobbyOwner(ctx.matchmaking, ctx.lobby_id),
// 	)
// 	ctx.connection = steam.NetworkingSockets_ConnectP2P(ctx.network_sockets, &id, 0, 0, nil)
// }

write :: proc(ctx: ^SteamCtx, data: []u8, allocator := context.allocator) {
}

read :: proc(ctx: ^SteamCtx, allocator := context.allocator) -> (data: []u8, ok: bool) {
	if ctx.connection == steam.HSteamNetConnection_Invalid do return

	msg := []^steam.SteamNetworkingMessage{nil}
	steam.NetworkingSockets_ReceiveMessagesOnConnection(
		ctx.network_sockets,
		ctx.connection,
		raw_data(msg),
		1,
	)


	return data, true
}
