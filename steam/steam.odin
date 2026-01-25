package steam

import steam "../vendor/steamworks/"
import "base:runtime"
import "core:c"
import "core:container/queue"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:net"
import "core:strings"


Event :: enum u8 {
	RelayInit,
	LobbyConnect,
	SocketConnect,
	Connected,
	SocketDisonnect,
	LobbyDisconnect,
	// RelayDeinit,
}

LOBBY_DATA_KEY :: "key"
SteamCtx :: struct {
	lobby_size:      u8,
	lobby_max_size:  u8,
	user:            ^steam.IUser,
	network_util:    ^steam.INetworkingUtils,
	network:         ^steam.INetworking,
	network_sockets: ^steam.INetworkingSockets,
	client:          ^steam.IClient,
	matchmaking:     ^steam.IMatchmaking,
	friends:         ^steam.IFriends,
	steam_id:        steam.CSteamID,
	lobby_id:        steam.CSteamID,
	host:            steam.SteamNetworkingIdentity,
	connection:      steam.HSteamNetConnection,
	socket:          steam.HSteamListenSocket,
	poll_group:      steam.HSteamNetPollGroup,
	// on_lobby_connecting: proc(ctx: ^SteamCtx),
	// on_lobby_connected:  proc(ctx: ^SteamCtx),
	// on_lobby_disconnect: proc(ctx: ^SteamCtx),
}


@(private)
g_ctx: runtime.Context

@(private)
g_arena: vmem.Arena

@(private)
g_queue: queue.Queue(Event)

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
		return
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
	g_ctx = context
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

	err := vmem.arena_init_growing(&g_arena)
	assert(err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)
	err = queue.init(&g_queue)
	assert(err == nil)

	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)
	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)

	steam.ManualDispatch_Init()
	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
}


update_callback :: proc(ctx: ^SteamCtx, arena: ^vmem.Arena) -> queue.Queue(Event) {
	context.allocator = vmem.arena_allocator(arena)
	temp := vmem.arena_temp_begin(arena)
	defer vmem.arena_temp_end(temp)

	h_pipe := steam.GetHSteamPipe()
	steam.ManualDispatch_RunFrame(h_pipe)

	callback: steam.CallbackMsg
	for (steam.ManualDispatch_GetNextCallback(h_pipe, &callback)) {
		if callback.iCallback == .SteamAPICallCompleted {
			completed_callback := cast(^steam.SteamAPICallCompleted)callback.pubParam
			param := make([dynamic]byte, completed_callback.cubParam)
			failed: bool
			ok: bool
			{ 	// Free directly after use, else pipe gets fills up
				ok = steam.ManualDispatch_GetAPICallResult(
					h_pipe,
					completed_callback.hAsyncCall,
					raw_data(param[:]),
					i32(completed_callback.cubParam),
					completed_callback.iCallback,
					&failed,
				)
				steam.ManualDispatch_FreeLastCallback(h_pipe)
			}
			if failed || !ok do continue
			callback_complete_handle(ctx, completed_callback, (&param[0]))

			continue
		}

		callback_handler(ctx, &callback)
		steam.ManualDispatch_FreeLastCallback(h_pipe)

	}


	// TODO(abdul): Cleanup events

	// for events.len > 0 {
	// 	event := queue.pop_front(&events)
	// 	switch event {
	// 	case .Connected:
	// 	case .RelayInit:
	// 	case .LobbyConnect:
	// 	case .SocketConnect:
	// 	case .SocketDisonnect:
	// 	case .LobbyDisconnect:
	//
	// 	}
	// }

	return g_queue
}

destroy :: proc(ctx: SteamCtx) {
	steam.Shutdown()
}

callback_complete_handle :: proc(
	ctx: ^SteamCtx,
	callback: ^steam.SteamAPICallCompleted,
	param: rawptr,
) {
	log.info("Completed Callback:", callback.iCallback)
	#partial switch callback.iCallback {
	case .LobbyEnter:
		data := (^steam.LobbyEnter)(param)
	case .LobbyCreated:
		data := (^steam.LobbyCreated)(param)
		assert(data.eResult == .OK)
		ctx.lobby_id = data.ulSteamIDLobby
	}
}

callback_handler :: proc(ctx: ^SteamCtx, callback: ^steam.CallbackMsg) {
	log.info("Callback:", callback.iCallback)
	#partial switch callback.iCallback {
	case .LobbyChatUpdate:
		// Server
		data := (^steam.LobbyChatUpdate)(callback.pubParam)
		log.info(data.rgfChatMemberStateChange)
		state := cast(steam.EChatMemberStateChange)(data.rgfChatMemberStateChange)
		switch state {
		case .Entered:
			log.infof("[HOST] %v has entered the lobby", data.ulSteamIDUserChanged)
			ctx.lobby_id = data.ulSteamIDLobby

			queue.push_back(&g_queue, Event.LobbyConnect)
		case .Disconnected, .Left, .Kicked, .Banned:
			log.infof("[HOST] %v has left the lobby", data.ulSteamIDUserChanged)

			ctx.lobby_id = 0
			queue.push_back(&g_queue, Event.SocketDisonnect)
		}
	case .SteamNetConnectionStatusChangedCallback:
		data := (^steam.SteamNetConnectionStatusChangedCallback)(callback.pubParam)
		log.debugf("%#w", data)
		info := data.info


		log.infof("Conn Update: %v -> %v", data.eOldState, info.eState)

		if ctx.socket != 0 && info.hListenSocket == ctx.socket {
			if data.eOldState == .None && info.eState == .Connecting {
				log.info("[HOST] New client connecting, accepting...")
				res := steam.NetworkingSockets_AcceptConnection(ctx.network_sockets, data.hConn)
				if res != .OK {
					log.error("[HOST] Failed to accept connection")
					steam.NetworkingSockets_CloseConnection(
						ctx.network_sockets,
						data.hConn,
						0,
						nil,
						false,
					)
				}
				queue.push_back(&g_queue, Event.SocketConnect)
			}
		}

		if info.eState == .ClosedByPeer || info.eState == .ProblemDetectedLocally {
			log.info("Connection lost/closed")
			steam.NetworkingSockets_CloseConnection(ctx.network_sockets, data.hConn, 0, nil, false)

			queue.push_back(&g_queue, Event.SocketDisonnect)
		}
	case .LobbyEnter:
		data := (^steam.LobbyEnter)(callback.pubParam)
		ctx.lobby_id = data.ulSteamIDLobby
		lobby_owner := steam.Matchmaking_GetLobbyOwner(ctx.matchmaking, data.ulSteamIDLobby)
		log.info("lobby_owner", lobby_owner)
		steam.NetworkingIdentity_SetSteamID(&ctx.host, lobby_owner)

		assert(!steam.NetworkingIdentity_IsInvalid(&ctx.host))

		ctx.socket = steam.NetworkingSockets_CreateListenSocketP2P(ctx.network_sockets, 0, 0, nil)
		assert(ctx.socket != 0)

		if lobby_owner == ctx.steam_id {
			log.infof("[HOST] Setting up lobby game server")

			steam.Matchmaking_SetLobbyGameServer(
				ctx.matchmaking,
				data.ulSteamIDLobby,
				0,
				0,
				ctx.steam_id,
			)

			log.infof("[HOST] Lobby game server set successfully")
		} else {
			assert(data.EChatRoomEnterResponse == u32(steam.EChatRoomEnterResponse.Success))
			log.infof("[PEER] entered lobby %v", data.ulSteamIDLobby)
			ctx.lobby_size = u8(
				steam.Matchmaking_GetNumLobbyMembers(ctx.matchmaking, data.ulSteamIDLobby),
			)

			log.infof("[PEER] connect to %v", ctx.connection)
			ctx.connection = steam.NetworkingSockets_ConnectP2P(
				ctx.network_sockets,
				&ctx.host,
				0,
				0,
				nil,
			)
			assert(ctx.connection != 0)
			log.infof("[PEER] trying connect to %v", ctx.connection)

			queue.push_back(&g_queue, Event.LobbyConnect)
		}

	case .GameLobbyJoinRequested:
		// connect to peer
		data := (^steam.GameLobbyJoinRequested)(callback.pubParam)
		name := steam.Friends_GetFriendPersonaName(ctx.friends, data.steamIDFriend)
		log.infof("[PEER] trying to connect to %v", name)
		steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
	}

}

create_lobby :: proc(ctx: ^SteamCtx) {
	status: steam.SteamRelayNetworkStatus
	for status.eAvail != .Current {
		_ = steam.NetworkingUtils_GetRelayNetworkStatus(ctx.network_util, &status)
	}

	_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, 4)
}
