package steam

import steam "./steamworks/"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:strings"

MAX_LOBBY_SIZE :: 8
LOBBY_DATA_KEY :: "key"

// Networking Send Flags (Constants since enum might not be exposed in bindings provided)
SendFlags :: enum i32 {
	Unreliable        = 0,
	NoNagle           = 1,
	UnreliableNoDelay = 2,
	Reliable          = 8,
}

// Connection states
ClientConnectionState :: enum {
	NotConnected,
	ConnectedPendingAuthentication,
	ConnectedAndAuthenticated,
}

// Message types
Message :: enum u32 {
	ClientBeginAuthentication = 1,
	ServerSendInfo            = 2,
	ServerPassAuthentication  = 3,
	ServerUpdateWorld         = 4,
	ClientSendLocalUpdate     = 5,
	ServerPlayerHitSun        = 6,
	ServerFailAuthentication  = 7,
	ServerExiting             = 8,
	VoiceChatData             = 9,
	P2PSendingTicket          = 10,
}

SteamCtx :: struct {
	user:             ^steam.IUser,
	network_util:     ^steam.INetworkingUtils,
	network:          ^steam.INetworking,
	network_sockets:  ^steam.INetworkingSockets,
	client:           ^steam.IClient,
	matchmaking:      ^steam.IMatchmaking,
	friends:          ^steam.IFriends,
	steam_id:         steam.CSteamID,
	lobby_id:         steam.CSteamID,
	socket:           steam.HSteamListenSocket,
	poll_group:       steam.HSteamNetPollGroup,
	user_identity:    steam.SteamNetworkingIdentity,
	host_identity:    steam.SteamNetworkingIdentity,
	connection:       steam.HSteamNetConnection,
	connection_state: ClientConnectionState,
	on_lobby_enter:   proc(ctx: SteamCtx),
	on_lobby_leave:   proc(ctx: SteamCtx),
	on_authenticated: proc(ctx: SteamCtx),
}

g_steam: SteamCtx
g_ctx: runtime.Context

// ===== DEBUG HOOKS =====

steam_debug_text_hook :: proc "c" (severity: c.int, debugText: cstring) {
	context = g_ctx
	log.info(string(debugText))

	if severity >= 1 {
		panic("steam err")
	}
}

steam_networtk_debug_to_log :: proc "c" (
	net_level: steam.ESteamNetworkingSocketsDebugOutputType,
	msg: cstring,
) {
	context = g_ctx

	level: log.Level
	#partial switch net_level {
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
	case:
		log.panicf("unexpected log level %v", net_level)
	}

	context.logger.procedure(context.logger.data, level, string(msg), context.logger.options)
}

// ===== INITIALIZATION =====

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
	ctx.connection_state = .NotConnected

	steam.NetworkingIdentity_SetSteamID(&ctx.user_identity, ctx.steam_id)

	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)

	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)

	steam.ManualDispatch_Init()

	// Initialize relay network access - required for P2P
	steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)
}

destroy :: proc(ctx: SteamCtx) {
	if ctx.poll_group != steam.HSteamNetPollGroup_Invalid {
		steam.NetworkingSockets_DestroyPollGroup(ctx.network_sockets, ctx.poll_group)
	}
	if ctx.socket != steam.HSteamListenSocket_Invalid {
		steam.NetworkingSockets_CloseListenSocket(ctx.network_sockets, ctx.socket)
	}
	steam.Shutdown()
}

// ===== CALLBACK HANDLING =====

update_callback :: proc(ctx: ^SteamCtx, arena: ^vmem.Arena) {
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

		callback_handle(ctx, &callback)
	}
}

callback_complete_handle :: proc(
	ctx: ^SteamCtx,
	callback: ^steam.SteamAPICallCompleted,
	param: rawptr,
) {
	#partial switch callback.iCallback {
	case .LobbyEnter:
		data := (^steam.LobbyEnter)(param)
		assert(data.EChatRoomEnterResponse == u32(steam.EChatRoomEnterResponse.Success))
		ctx.lobby_id = data.ulSteamIDLobby
		log.infof("Entered lobby: %v", ctx.lobby_id)
	case .LobbyDataUpdate:
	case .LobbyCreated:
		data := (^steam.LobbyCreated)(param)
		assert(data.eResult == .OK)
		ctx.lobby_id = data.ulSteamIDLobby
		log.infof("Created lobby: %v", ctx.lobby_id)
	}
	log.info("Completed Callback:", callback.iCallback)
}

callback_handle :: proc(ctx: ^SteamCtx, callback: ^steam.CallbackMsg) {
	#partial switch callback.iCallback {
	case .SteamNetConnectionStatusChangedCallback:
		data := (^steam.SteamNetConnectionStatusChangedCallback)(callback.pubParam)

		// Direct struct access for info (fields stripped of 'm_' prefix)
		info := data.info
		old_state := data.eOldState

		log.infof(
			"Connection Status: hConn=%v, State=%v->%v, ListenSocket=%v",
			data.hConn,
			old_state,
			info.eState,
			info.hListenSocket,
		)

		// ===== HOST LOGIC: Incoming connection =====
		is_connecting :=
			info.hListenSocket != steam.HSteamListenSocket_Invalid &&
			info.eState == .Connecting &&
			old_state == .None

		if is_connecting {
			log.infof("Incoming connection from %v. Accepting...", info.identityRemote)
			res := steam.NetworkingSockets_AcceptConnection(ctx.network_sockets, data.hConn)

			if res != .OK {
				log.errorf("Failed to accept connection: %v", res)
				steam.NetworkingSockets_CloseConnection(
					ctx.network_sockets,
					data.hConn,
					i32(steam.ESteamNetConnectionEnd.AppException_Generic),
					"Failed to accept",
					false,
				)
				return
			}

			// CRITICAL: Add to poll group
			steam.NetworkingSockets_SetConnectionPollGroup(
				ctx.network_sockets,
				data.hConn,
				ctx.poll_group,
			)

			ctx.connection = data.hConn
			log.info("Connection accepted! Sending server info...")

			// Send server info immediately
			send_server_info(ctx)

			if ctx.on_lobby_enter != nil {
				ctx.on_lobby_enter(ctx^)
			}
			return
		}

		// ===== CLIENT LOGIC: Connection succeeded =====
		is_connected :=
			info.hListenSocket == steam.HSteamListenSocket_Invalid &&
			old_state == .Connecting &&
			info.eState == .Connected

		if is_connected {
			log.info("Connection established! Sending authentication...")

			// Send authentication message
			send_client_authentication(ctx)

			// Update state
			ctx.connection_state = .ConnectedPendingAuthentication
			return
		}

		// ===== CLIENT LOGIC: Connection failed =====
		is_failed :=
			info.hListenSocket == steam.HSteamListenSocket_Invalid &&
			(info.eState == .ClosedByPeer || info.eState == .ProblemDetectedLocally)

		if is_failed {
			// Fixed field name: szEndDebug (no m_)
			log.errorf("Connection failed: %v (State: %v)", info.szEndDebug, info.eState)

			if ctx.connection_state != .NotConnected {
				if ctx.on_lobby_leave != nil {
					ctx.on_lobby_leave(ctx^)
				}
			}
			ctx.connection_state = .NotConnected
			ctx.connection = steam.HSteamNetConnection_Invalid
			return
		}

		// ===== HOST/CLIENT: Disconnect =====
		is_closed :=
			info.hListenSocket != steam.HSteamListenSocket_Invalid &&
			old_state == .Connected &&
			(info.eState == .ClosedByPeer || info.eState == .ProblemDetectedLocally)

		if is_closed {
			log.info("Connection closed")
			steam.NetworkingSockets_CloseConnection(ctx.network_sockets, data.hConn, 0, nil, false)
			if data.hConn == ctx.connection {
				ctx.connection = steam.HSteamNetConnection_Invalid
				if ctx.on_lobby_leave != nil {
					ctx.on_lobby_leave(ctx^)
				}
			}
		}

	case .GameLobbyJoinRequested:
		// Client: Connect to peer when joining lobby
		data := (^steam.GameLobbyJoinRequested)(callback.pubParam)
		steam.NetworkingIdentity_SetSteamID(&ctx.host_identity, data.steamIDFriend)

		assert(!steam.NetworkingIdentity_IsInvalid(&ctx.host_identity))

		log.infof("Attempting to connect to host %v...", data.steamIDFriend)

		// Reset connection state
		ctx.connection_state = .NotConnected

		// Connect to P2P
		ctx.connection = steam.NetworkingSockets_ConnectP2P(
			ctx.network_sockets,
			&ctx.host_identity,
			0,
			0,
			nil,
		)

		// Join lobby
		_ = steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)

		name := steam.Friends_GetFriendPersonaName(ctx.friends, data.steamIDFriend)
		log.infof("Trying to connect to user %v (%v).", name, data.steamIDFriend)
	}

	log.info("Callback:", callback.iCallback)
}

// ===== HOSTING =====

host :: proc(ctx: ^SteamCtx) {
	log.info("Creating lobby...")
	_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, 4)

	log.info("Creating poll group...")
	ctx.poll_group = steam.NetworkingSockets_CreatePollGroup(ctx.network_sockets)

	log.info("Creating listen socket...")
	ctx.socket = steam.NetworkingSockets_CreateListenSocketP2P(ctx.network_sockets, 0, 0, nil)

	log.infof("Listen socket created: %v", ctx.socket)
	log.infof("Poll group created: %v", ctx.poll_group)
}

// ===== MESSAGE SENDING =====

// Helper to write u32 to byte buffer
write_u32_le :: proc(buf: []u8, offset: int, val: u32) {
	ptr := cast(^u32)(&buf[offset])
	ptr^ = val
}

// Helper to write u64 to byte buffer
write_u64_le :: proc(buf: []u8, offset: int, val: u64) {
	ptr := cast(^u64)(&buf[offset])
	ptr^ = val
}

send_server_info :: proc(ctx: ^SteamCtx) {
	if ctx.connection == steam.HSteamNetConnection_Invalid {
		log.warn("Cannot send server info: not connected")
		return
	}

	// Build message: [message_type: u32][steam_id: u64] = 12 bytes
	msg_buffer: [12]u8
	write_u32_le(msg_buffer[:], 0, u32(Message.ServerSendInfo))
	write_u64_le(msg_buffer[:], 4, u64(ctx.steam_id))

	res := steam.NetworkingSockets_SendMessageToConnection(
		ctx.network_sockets,
		ctx.connection,
		raw_data(&msg_buffer),
		12,
		i32(SendFlags.Reliable),
		nil,
	)

	if res != .OK {
		log.errorf("Failed to send server info: %v", res)
	} else {
		log.info("Sent server info to client")
	}
}

send_client_authentication :: proc(ctx: ^SteamCtx) {
	if ctx.connection == steam.HSteamNetConnection_Invalid {
		log.warn("Cannot send authentication: not connected")
		return
	}

	// Build message: [message_type: u32][steam_id: u64] = 12 bytes
	msg_buffer: [12]u8
	write_u32_le(msg_buffer[:], 0, u32(Message.ClientBeginAuthentication))
	write_u64_le(msg_buffer[:], 4, u64(ctx.steam_id))

	res := steam.NetworkingSockets_SendMessageToConnection(
		ctx.network_sockets,
		ctx.connection,
		raw_data(&msg_buffer),
		12,
		i32(SendFlags.Reliable),
		nil,
	)

	if res != .OK {
		log.errorf("Failed to send authentication: %v", res)
	} else {
		log.info("Sent client authentication")
	}
}

send_authentication_success :: proc(ctx: ^SteamCtx, player_position: u32) {
	if ctx.connection == steam.HSteamNetConnection_Invalid {
		log.warn("Cannot send auth success: not connected")
		return
	}

	// Build message: [message_type: u32][player_position: u32] = 8 bytes
	msg_buffer: [8]u8
	write_u32_le(msg_buffer[:], 0, u32(Message.ServerPassAuthentication))
	write_u32_le(msg_buffer[:], 4, player_position)

	res := steam.NetworkingSockets_SendMessageToConnection(
		ctx.network_sockets,
		ctx.connection,
		raw_data(&msg_buffer),
		8,
		i32(SendFlags.Reliable),
		nil,
	)

	if res != .OK {
		log.errorf("Failed to send auth success: %v", res)
	} else {
		log.infof("Sent authentication success for player %v", player_position)
	}
}

write :: proc(ctx: ^SteamCtx, data: []u8, allocator := context.allocator) {
	if ctx.connection == steam.HSteamNetConnection_Invalid {
		log.warn("Cannot write: not connected")
		return
	}

	// Only allow writes if authenticated
	if ctx.connection_state != .ConnectedAndAuthenticated {
		log.warn("Cannot write: not authenticated")
		return
	}

	res := steam.NetworkingSockets_SendMessageToConnection(
		ctx.network_sockets,
		ctx.connection,
		raw_data(data),
		u32(len(data)), // Explicit int cast
		i32(SendFlags.Unreliable),
		nil,
	)

	if res != .OK {
		log.errorf("Failed to send message: %v", res)
	}
}

// ===== MESSAGE READING =====

read :: proc(ctx: ^SteamCtx, allocator := context.allocator) -> (data: []u8, ok: bool) {
	if ctx.connection == steam.HSteamNetConnection_Invalid do return

	// Check relay network status
	if ctx.poll_group != steam.HSteamNetPollGroup_Invalid {
		relay_status := steam.NetworkingUtils_GetRelayNetworkStatus(ctx.network_util, nil)
		if relay_status != .Current {
			log.infof("Waiting for relay network... status: %v", relay_status)
			return data, false
		}

		// Use poll group for receiving
		msg_ptr: ^steam.SteamNetworkingMessage

		num_msgs := steam.NetworkingSockets_ReceiveMessagesOnPollGroup(
			ctx.network_sockets,
			ctx.poll_group,
			&msg_ptr,
			1,
		)

		if num_msgs > 0 {
			msg := msg_ptr
			defer {
				// Direct struct field access to release function
				if msg.pfnRelease != nil {
					msg.pfnRelease(msg)
				}
			}

			// Direct struct field access for data and size
			size := msg.cbSize
			if size < 4 do return // Too short for message header

			// Cast pData to u32* for reading the message type
			msg_data := cast(^u32)(msg.pData)
			msg_type := msg_data^ // Dereference pointer

			log.infof(
				"Received message: type=%v, size=%d, from=%v",
				Message(msg_type),
				size,
				msg.identityPeer,
			)

			// Handle different message types
			#partial switch Message(msg_type) {
			case .ServerSendInfo:
				log.info("Received server info")
				ok = true

			case .ServerPassAuthentication:
				data_slice := make([]u8, size, allocator)
				mem.copy(raw_data(data_slice), msg.pData, int(size)) // Explicit int cast

				ctx.connection_state = .ConnectedAndAuthenticated
				if ctx.on_authenticated != nil {
					ctx.on_authenticated(ctx^)
				}

				log.info("Authentication successful!")
				return data_slice, true

			case .ServerFailAuthentication:
				log.error("Server rejected authentication")
				if ctx.on_lobby_leave != nil {
					ctx.on_lobby_leave(ctx^)
				}

			case .ServerUpdateWorld:
				data_slice := make([]u8, size, allocator)
				mem.copy(raw_data(data_slice), msg.pData, int(size)) // Explicit int cast
				return data_slice, true

			case .ClientBeginAuthentication:
				log.info("Received client authentication")
				// Parse SteamID from message (skip first 4 bytes for type)
				if size >= 12 { 	// message_type (4) + steam_id (8)
					// Access the u64 after the u32
					steam_id_ptr := cast(^u64)(msg_data)
					client_steamid := steam_id_ptr^
					log.infof("Client SteamID: %v", client_steamid)
				}
				send_authentication_success(ctx, 0) // player_position = 0
			}
		}
	}

	return data, false
}

// ===== UTILITIES =====

check_relay_status :: proc(ctx: ^SteamCtx) -> bool {
	if ctx.network_util == nil do return false

	status := steam.NetworkingUtils_GetRelayNetworkStatus(ctx.network_util, nil)

	// Fixed .Never to .NeverTried based on compiler error logs
	#partial switch status {
	case .Current:
		return true
	case .Attempting:
		log.info("Attempting to connect to relay network...")
		return false
	case .NeverTried:
		log.warn("Relay network not initialized")
		return false
	case:
		log.errorf("Relay network error: %v", status)
		return false
	}
}

debug_connection_state :: proc(ctx: ^SteamCtx) {
	log.infof("=== Connection State Debug ===")
	log.infof("Steam ID: %v", ctx.steam_id)
	log.infof("Connection handle: %v", ctx.connection)
	log.infof("Poll group: %v", ctx.poll_group)
	log.infof("Listen socket: %v", ctx.socket)
	log.infof("Connection state: %v", ctx.connection_state)

	// Get connection info
	if ctx.connection != steam.HSteamNetConnection_Invalid {
		info: steam.SteamNetConnectionInfo
		if steam.NetworkingSockets_GetConnectionInfo(ctx.network_sockets, ctx.connection, &info) {
			log.infof("Connection state: %v", info.eState)
			// Fixed field name: identityRemote (no m_)
			log.infof("Remote identity: %v", info.identityRemote)
			// Fixed field name: eEndReason (no m_)
			log.infof("End reason: %v", info.eEndReason)
			// Fixed field name: szEndDebug (no m_)
			log.infof("End debug: %v", info.szEndDebug)
		}
	}

	// Get relay status
	if ctx.network_util != nil {
		status := steam.NetworkingUtils_GetRelayNetworkStatus(ctx.network_util, nil)
		log.infof("Relay network status: %v", status)
	}

	log.infof("===============================")
}
