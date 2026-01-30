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
	// None,
	Connecting,
	Connected,
	Disconnected,
	PeerDisconnected,
	PeerConnected,
	HostDisconnected,
}

Actions :: enum u8 {
	Connect,
}

LOBBY_DATA_KEY :: "key"
SteamFlagBits :: enum u8 {
	Server,
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

	steam.ManualDispatch_Init()
	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
}


update_callback :: proc(ctx: ^SteamCtx, arena: ^vmem.Arena) {
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
	if .Server in ctx.flags do return
	if ctx.connection == nil do return
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

		str, _ := strings.clone_from_ptr((^u8)(msg.pData), int(msg.cbSize))
		log.infof("[PEER] Recived msg %v", str)
	}

	return
}

disconnect :: proc(ctx: ^SteamCtx) {
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

	ctx.flags -= {.Server}

	steam.NetworkingSockets_CloseListenSocket(ctx.network_sockets, ctx.socket)
	steam.NetworkingSockets_DestroyPollGroup(ctx.network_sockets, ctx.poll_group)
}


deinit :: proc(ctx: ^SteamCtx) {
	disconnect(ctx)
	queue.destroy(&ctx.event_queue)
	vmem.arena_destroy(&g_arena)
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
			log.infof("[ALL] %v has entered the lobby", data.ulSteamIDUserChanged)
			ctx.lobby_id = data.ulSteamIDLobby
			queue.push_back(&ctx.event_queue, Event.PeerConnected)
		case .Disconnected, .Left, .Kicked, .Banned:
			log.infof("[ALL] %v has left the lobby", data.ulSteamIDUserChanged)
			queue.push_back(&ctx.event_queue, Event.PeerDisconnected)
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


		if is_host && can_accept {
			log.info("[HOST] New client connecting, accepting...")
			res := steam.NetworkingSockets_AcceptConnection(ctx.network_sockets, data.hConn)
			if res != .OK {
				log.error("[HOST] Failed to accept connection")
				disconnect(ctx)
			}

			// TODO(Abdul) check if identify is valid
			remote_id := steam.NetworkingIdentity_GetSteamID(&info.identityRemote)
			for &peer in ctx.connection.(ConnectionsToClient) {
				if peer.id == remote_id {
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
				queue.push_back(&ctx.event_queue, Event.HostDisconnected)
			} else {
				queue.push_back(&ctx.event_queue, Event.Disconnected)
			}
		}

		if !is_host && data.eOldState == .FindingRoute && info.eState == .Connected {
			queue.push_back(&ctx.event_queue, Event.Connected)
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

		ctx.max_lobby_size = u16(
			steam.Matchmaking_GetLobbyMemberLimit(ctx.matchmaking, data.ulSteamIDLobby),
		)

		ctx.lobby_size = u16(
			steam.Matchmaking_GetNumLobbyMembers(ctx.matchmaking, data.ulSteamIDLobby),
		)

		g_alloc := vmem.arena_allocator(&g_arena)

		if lobby_owner == ctx.steam_id { 	// HOST
			log.infof("[HOST] Setting up lobby game server for %v", ctx.steam_id)
			ctx.connection = make(ConnectionsToClient, ctx.max_lobby_size, g_alloc)

			for &peer, i in ctx.connection.(ConnectionsToClient) {
				peer.id = steam.Matchmaking_GetLobbyMemberByIndex(
					ctx.matchmaking,
					data.ulSteamIDLobby,
					i32(i),
				)
			}
			queue.push_back(&ctx.event_queue, Event.Connected)
			break
		}

		// PEER
		assert(data.EChatRoomEnterResponse == u32(steam.EChatRoomEnterResponse.Success))
		log.infof("[Peer] Setting up lobby game server")


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
		queue.push_back(&ctx.event_queue, Event.Connecting)
	}

}

create_lobby :: proc(ctx: ^SteamCtx, max_lobby_size: u16 = 8) {
	ctx.flags += {.Server}
	_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, i32(max_lobby_size))
}


write :: proc(ctx: ^SteamCtx) {
	msg := "hello form Host"

	switch conn in ctx.connection {
	case ConnectionToHost:
		log.info("[Peer] Send msg:", msg)
		res := steam.NetworkingSockets_SendMessageToConnection(
			ctx.network_sockets,
			conn.connection,
			raw_data(msg),
			u32(len(msg)),
			steam.nSteamNetworkingSend_Reliable,
			nil,
		)
		if res != .OK {
			log.error("[Peer] Cound not send Msg", res)
			assert(false)
		}
	case ConnectionsToClient:
		log.info("[Host] Send msg to all:", msg)
		for p in conn {
			res := steam.NetworkingSockets_SendMessageToConnection(
				ctx.network_sockets,
				p.connection,
				raw_data(msg),
				u32(len(msg)),
				steam.nSteamNetworkingSend_Reliable,
				nil,
			)
			if res != .OK {
				log.error("[Host] Cound not send Msg", res)
				assert(false)
			}
		}
	}

}
