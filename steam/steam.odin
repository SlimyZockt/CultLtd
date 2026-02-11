package steam

import steam "../vendor/steamworks/"
import "base:runtime"
import "core:c"
import "core:container/queue"
import "core:log"
import vmem "core:mem/virtual"

Event :: struct {
	type: enum u8 {
		Created,
		ConnectingToHost,
		PeerDisconnected,
		PeerConnected,
		DisconnectedFormHost,
		ConnectedToHost,
	},
	// peer: Maybe(Peer),
	id:   steam.CSteamID,
}


LOBBY_DATA_KEY :: "key"
SteamFlagBits :: enum u8 {
	Host,
}

SteamFlags :: bit_set[SteamFlagBits;u8]


Peer :: struct {
	connection: steam.HSteamNetConnection,
	id:         steam.CSteamID,
}

ConnectionsToClient :: []Peer
ConnectionToHost :: Peer

SteamCtx :: struct {
	lobby_size:      u16,
	max_lobby_size:  u16,
	flags:           SteamFlags,
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
	host_id:         steam.CSteamID,
	socket:          steam.HSteamListenSocket,
	poll_group:      steam.HSteamNetPollGroup,
	event_queue:     queue.Queue(Event),
	connection:      union {
		ConnectionsToClient,
		ConnectionToHost,
	},
}


@(private)
g_ctx: runtime.Context

@(private)
g_arena: vmem.Arena

@(private)
steam_ctx: SteamCtx

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
			cast(cstring)&err_msg[0],
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

	assert(ctx.steam_id != 0)

	err := vmem.arena_init_growing(&g_arena)
	assert(err == nil)
	context.allocator = vmem.arena_allocator(&g_arena)
	err = queue.init(&ctx.event_queue)
	assert(err == nil)

	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)
	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)
	ctx.poll_group = steam.NetworkingSockets_CreatePollGroup(ctx.network_sockets)

	steam.ManualDispatch_Init()
	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
}


update_callback :: proc(ctx: ^SteamCtx) -> ^queue.Queue(Event) {
	context.allocator = vmem.arena_allocator(&g_arena)
	temp := vmem.arena_temp_begin(&g_arena)
	defer vmem.arena_temp_end(temp)

	h_pipe := steam.GetHSteamPipe()
	steam.ManualDispatch_RunFrame(h_pipe)

	// steam.ManualDispatch_FreeLastCallback()

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


	return &ctx.event_queue
}

ReceiveMsgCallback :: #type proc(msg: ^steam.SteamNetworkingMessage, user_data: rawptr)
process_received_msg :: proc(
	ctx: SteamCtx,
	on_receive_msg: ReceiveMsgCallback,
	user_data: rawptr,
) {
	if ctx.connection == nil do return
	// if .Connected not_in ctx.flags do return &ctx.event_queue
	// TODO(abdul): Implement Receive MSG's form clients
	if .Host in ctx.flags {
		MAX_MESSAGE_COUNT :: 64
		msgs: [MAX_MESSAGE_COUNT]^steam.SteamNetworkingMessage
		assert(ctx.poll_group != 0)
		msg_count := steam.NetworkingSockets_ReceiveMessagesOnPollGroup(
			ctx.network_sockets,
			ctx.poll_group,
			raw_data(&msgs),
			MAX_MESSAGE_COUNT,
		)
		if msg_count <= 0 do return
		for i in 0 ..< msg_count {
			msg := msgs[i]
			defer steam.NetworkingMessage_t_Release(msg)

			on_receive_msg(msg, user_data)
		}
		return
	}

	MAX_MESSAGE_COUNT :: 64
	msgs: [MAX_MESSAGE_COUNT]^steam.SteamNetworkingMessage
	msg_count := steam.NetworkingSockets_ReceiveMessagesOnConnection(
		ctx.network_sockets,
		ctx.connection.(ConnectionToHost).connection,
		raw_data(&msgs),
		MAX_MESSAGE_COUNT,
	)
	if msg_count <= 0 do return
	for i in 0 ..< msg_count {
		msg := msgs[i]
		defer steam.NetworkingMessage_t_Release(msg)

		on_receive_msg(msg, user_data)
	}
}

disconnect :: proc(ctx: ^SteamCtx) {
	ctx.flags -= {.Host}
	steam.Matchmaking_LeaveLobby(ctx.matchmaking, ctx.lobby_id)

	switch conn in ctx.connection {
	case ConnectionsToClient:
		for p in conn {
			steam.NetworkingSockets_CloseConnection(
				ctx.network_sockets,
				p.connection,
				0,
				nil,
				false,
			)
		}
	case ConnectionToHost:
		steam.NetworkingSockets_CloseConnection(
			ctx.network_sockets,
			conn.connection,
			0,
			nil,
			false,
		)
	}

	ctx.connection = nil

	steam.NetworkingSockets_CloseListenSocket(ctx.network_sockets, ctx.socket)
	steam.NetworkingSockets_DestroyPollGroup(ctx.network_sockets, ctx.poll_group)
}


deinit :: proc(ctx: ^SteamCtx) {
	disconnect(ctx)

	queue.destroy(&ctx.event_queue)
	vmem.arena_destroy(&g_arena)

	h_pipe := steam.GetHSteamPipe()
	steam.ManualDispatch_RunFrame(h_pipe)
	callback: steam.CallbackMsg
	for (steam.ManualDispatch_GetNextCallback(h_pipe, &callback)) {
		steam.ManualDispatch_FreeLastCallback(h_pipe)
	}

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
	case .LobbyCreated:
	}
}

callback_handler :: proc(ctx: ^SteamCtx, callback: ^steam.CallbackMsg) {

	log.info("Callback:", callback.iCallback)
	#partial switch callback.iCallback {
	case .LobbyCreated:
		data := (^steam.LobbyCreated)(callback.pubParam)
		assert(data.eResult == .OK)

	case .LobbyChatUpdate:
		// Server
		data := (^steam.LobbyChatUpdate)(callback.pubParam)
		log.info(data.rgfChatMemberStateChange)
		state := cast(steam.EChatMemberStateChange)(data.rgfChatMemberStateChange)
		switch state {
		case .Entered:
			log.infof("[ALL] %v has entered the lobby", data.ulSteamIDUserChanged)
			ctx.lobby_id = data.ulSteamIDLobby
		case .Disconnected, .Left, .Kicked, .Banned:
			log.infof("[ALL] %v has left the lobby", data.ulSteamIDUserChanged)
		}
	case .SteamNetConnectionStatusChangedCallback:
		data := (^steam.SteamNetConnectionStatusChangedCallback)(callback.pubParam)
		info := data.info
		assert(ctx.socket != 0)

		log.infof("Connection Update: %v -> %v", data.eOldState, info.eState)

		is_host := info.hListenSocket == ctx.socket
		can_accept :=
			ctx.lobby_size <= ctx.max_lobby_size &&
			info.hListenSocket != steam.HSteamListenSocket_Invalid &&
			data.eOldState == .None &&
			info.eState == .Connecting

		// TODO(Abdul) check if identify is valid
		remote_id := steam.NetworkingIdentity_GetSteamID(&info.identityRemote)
		ctx.host_id = steam.NetworkingIdentity_GetSteamID(&ctx.host)

		if is_host && can_accept {
			log.info("[HOST] New client connecting, accepting...")
			res := steam.NetworkingSockets_AcceptConnection(ctx.network_sockets, data.hConn)
			if res != .OK {
				log.error("[HOST] Failed to accept connection")
				disconnect(ctx)
			}

			for &peer in ctx.connection.(ConnectionsToClient) {
				if peer.id == 0 {
					peer.id = remote_id
					peer.connection = data.hConn
					break
				}
			}

			ok := steam.NetworkingSockets_SetConnectionPollGroup(
				ctx.network_sockets,
				data.hConn,
				ctx.poll_group,
			)

			assert(ok)


		}

		has_error := info.eState == .ClosedByPeer || info.eState == .ProblemDetectedLocally
		if has_error {
			log.info("Connection lost/closed")
			disconnect(ctx)
			if is_host {
				queue.push_back(&ctx.event_queue, Event{type = .PeerDisconnected, id = remote_id})
			} else {
				queue.push_back(
					&ctx.event_queue,
					Event{type = .DisconnectedFormHost, id = ctx.host_id},
				)
			}
		}

		if !is_host && data.eOldState == .FindingRoute && info.eState == .Connected {
			queue.push_back(&ctx.event_queue, Event{type = .ConnectedToHost, id = ctx.host_id})
		}


		if is_host && data.eOldState == .FindingRoute && info.eState == .Connected {
			queue.push_back(&ctx.event_queue, Event{type = .PeerConnected, id = remote_id})
		}

	case .LobbyEnter:
		data := (^steam.LobbyEnter)(callback.pubParam)
		ctx.lobby_id = data.ulSteamIDLobby
		lobby_owner := steam.Matchmaking_GetLobbyOwner(ctx.matchmaking, data.ulSteamIDLobby)
		steam.NetworkingIdentity_SetSteamID(&ctx.host, lobby_owner)

		assert(!steam.NetworkingIdentity_IsInvalid(&ctx.host))

		ctx.socket = steam.NetworkingSockets_CreateListenSocketP2P(ctx.network_sockets, 0, 0, nil)

		assert(ctx.socket != 0)

		ctx.max_lobby_size = u16(
			steam.Matchmaking_GetLobbyMemberLimit(ctx.matchmaking, data.ulSteamIDLobby),
		)

		ctx.lobby_size = u16(
			steam.Matchmaking_GetNumLobbyMembers(ctx.matchmaking, data.ulSteamIDLobby),
		)

		// remote_id := steam.NetworkingIdentity_GetSteamID(&data.)

		if lobby_owner == ctx.steam_id { 	// HOST
			if ctx.lobby_size <= 1 {

				queue.push_back(&ctx.event_queue, Event{type = .Created})
				break
			}

			// queue.push_back(&ctx.event_queue, Event{type = .PeerConnected})
			break
		}

		// PEER
		assert(data.EChatRoomEnterResponse == u32(steam.EChatRoomEnterResponse.Success))
		log.infof("[PEER] Setting up lobby game server")


		log.infof("[PEER] connect to %v", ctx.connection)
		ctx.connection = ConnectionToHost {
			steam.NetworkingSockets_ConnectP2P(ctx.network_sockets, &ctx.host, 0, 0, nil),
			lobby_owner,
		}

		log.infof("[PEER] trying connect to %v", ctx.connection)

	case .GameLobbyJoinRequested:
		// connect to peer
		data := (^steam.GameLobbyJoinRequested)(callback.pubParam)
		name := steam.Friends_GetFriendPersonaName(ctx.friends, data.steamIDFriend)
		log.infof("[PEER] trying to connect to %v", name)
		steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
		queue.push_back(&ctx.event_queue, Event{type = .ConnectingToHost})
	}

}

create_lobby :: proc(ctx: ^SteamCtx, max_lobby_size: u16 = 8) {
	ctx.flags += {.Host}
	ctx.max_lobby_size = max_lobby_size
	g_alloc := vmem.arena_allocator(&g_arena)
	ctx.connection = make_slice(ConnectionsToClient, ctx.max_lobby_size, g_alloc)
	_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, i32(max_lobby_size))
}


write :: proc(ctx: ^SteamCtx, data: ^$T, size: u32) {
	switch conn in ctx.connection {
	case ConnectionToHost:
		res := steam.NetworkingSockets_SendMessageToConnection(
			ctx.network_sockets,
			conn.connection,
			data,
			size,
			steam.nSteamNetworkingSend_Reliable,
			nil,
		)
		if res != .OK {
			log.panic("[Peer] Cound not send Msg", res)
		}
	case ConnectionsToClient:
		for p in conn {
			if p.connection == 0 do continue
			if p.id == 0 do continue

			res := steam.NetworkingSockets_SendMessageToConnection(
				ctx.network_sockets,
				p.connection,
				data,
				size,
				steam.nSteamNetworkingSend_Reliable,
				nil,
			)
			if res != .OK {
				log.panic("[Host] Cound not send Msg", res)
			}
		}
	}

}
