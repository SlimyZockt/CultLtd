package steam

import steam "../vendor/steamworks/"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:net"
import "core:strings"


LOBBY_DATA_KEY :: "key"
SteamCtx :: struct {
	lobby_size:          u8,
	// lobby_max_size:      u8,
	address:             u32,
	user:                ^steam.IUser,
	network_util:        ^steam.INetworkingUtils,
	network:             ^steam.INetworking,
	network_sockets:     ^steam.INetworkingSockets,
	client:              ^steam.IClient,
	matchmaking:         ^steam.IMatchmaking,
	friends:             ^steam.IFriends,
	steam_id:            steam.CSteamID,
	lobby_id:            steam.CSteamID,
	on_lobby_connect:    proc(ctx: ^SteamCtx),
	on_lobby_disconnect: proc(ctx: ^SteamCtx),
}

@(private)
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

	assert(ctx.on_lobby_connect != nil)
	assert(ctx.on_lobby_disconnect != nil)

	// steam.NetworkingUtils_InitRelayNetworkAccess(ctx.network_util)

	steam.Client_SetWarningMessageHook(ctx.client, steam_debug_text_hook)
	steam.NetworkingUtils_SetDebugOutputFunction(
		ctx.network_util,
		.Everything,
		steam_networtk_debug_to_log,
	)

	steam.ManualDispatch_Init()

}

update_callback :: proc(ctx: ^SteamCtx, arena: ^vmem.Arena) {
	temp := vmem.arena_temp_begin(arena)
	context.allocator = vmem.arena_allocator(arena)
	defer vmem.arena_temp_end(temp)

	h_pipe := steam.GetHSteamPipe()
	steam.ManualDispatch_RunFrame(h_pipe)

	callback: steam.CallbackMsg
	for (steam.ManualDispatch_GetNextCallback(h_pipe, &callback)) {
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
			steam.ManualDispatch_FreeLastCallback(h_pipe)

			continue
		}

		callback_handler(ctx, &callback)
		steam.ManualDispatch_FreeLastCallback(h_pipe)

	}
}

destroy :: proc(ctx: SteamCtx) {
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
		assert(data.EChatRoomEnterResponse == u32(steam.EChatRoomEnterResponse.Success))
		log.infof("I entered lobby %v", data.ulSteamIDLobby)
		ctx.lobby_size = u8(
			steam.Matchmaking_GetNumLobbyMembers(ctx.matchmaking, data.ulSteamIDLobby),
		)


		ip: u32
		_port: u16
		_id: steam.CSteamID
		ok := steam.Matchmaking_GetLobbyGameServer(
			ctx.matchmaking,
			data.ulSteamIDLobby,
			&ip,
			&_port,
			&_id,
		)
		if ok {
			log.info(transmute([4]u8)(ip))
			ctx.address = ip
			ctx.on_lobby_connect(ctx)
		}

	case .LobbyCreated:
		data := (^steam.LobbyCreated)(param)
		assert(data.eResult == .OK)
		ctx.lobby_id = data.ulSteamIDLobby
		id_str := fmt.ctprintf("%v", ctx.steam_id)
	// steam.Matchmaking_SetLobbyData(ctx.matchmaking, ctx.lobby_id, LOBBY_DATA_KEY, id_str)
	}
	log.info("Completed Callback:", callback.iCallback)

}


callback_handler :: proc(ctx: ^SteamCtx, callback: ^steam.CallbackMsg) {
	#partial switch callback.iCallback {
	case .LobbyChatUpdate:
		// Server
		data := (^steam.LobbyChatUpdate)(callback.pubParam)
		log.info(data.rgfChatMemberStateChange)
		state := cast(steam.EChatMemberStateChange)(data.rgfChatMemberStateChange)
		switch state {
		case .Entered:
			log.infof("%v has entered the lobby", data.ulSteamIDUserChanged)
			assert(ctx.on_lobby_connect != nil)
			ctx.lobby_id = data.ulSteamIDLobby
			ctx.on_lobby_connect(ctx)
		case .Disconnected, .Left, .Kicked, .Banned:
			log.infof("%v has left the lobby", data.ulSteamIDUserChanged)
			assert(ctx.on_lobby_disconnect != nil)
			ctx.lobby_id = 0
			ctx.on_lobby_disconnect(ctx)
		}
	case .LobbyGameCreated:
		data := (^steam.LobbyGameCreated)(callback.pubParam)
		log.infof("LobbyGameCreated: %v", transmute([4]u8)(data.unIP))
		ctx.address = data.unIP
		ctx.on_lobby_connect(ctx)

	case .LobbyEnter:
		data := (^steam.LobbyEnter)(callback.pubParam)
		if steam.Matchmaking_GetLobbyOwner(ctx.matchmaking, data.ulSteamIDLobby) == ctx.steam_id {
			//HACK(Abdul): get IP address via dial. Switch to interface lookup (it isn't implemented)
			target := net.IP4_Address{1, 1, 1, 1}
			sock, err := net.dial_tcp_from_address_and_port(target, 80)
			defer net.close(sock)
			if err == nil {
				fmt.printfln("Error dialing: %v", err)
				target = net.IP4_Loopback
			}
			local_endpoint, ep_err := net.bound_endpoint(sock)
			if ep_err != nil {
				fmt.printfln("Error getting bound endpoint: %v", ep_err)
				target = net.IP4_Loopback

				return
			}
			address, ok := local_endpoint.address.(net.IP4_Address)
			log.infof("local IP is: %v", address)
			assert(ok)

			tmp := transmute(u32be)(address)
			steam.Matchmaking_SetLobbyGameServer(
				ctx.matchmaking,
				ctx.lobby_id,
				u32(tmp),
				7777,
				ctx.steam_id,
			)
			log.info("SetLobbyGameServer called successfully.")
		}


	case .LobbyDataUpdate:
		// Server & Peer
		data := (^steam.LobbyDataUpdate)(callback.pubParam)
	case .GameLobbyJoinRequested:
		// connect to peer
		data := (^steam.GameLobbyJoinRequested)(callback.pubParam)
		name := steam.Friends_GetFriendPersonaName(ctx.friends, data.steamIDFriend)
		log.infof("trying to connect to user %v (%v).", name, data.steamIDFriend)
		steam.Matchmaking_JoinLobby(ctx.matchmaking, data.steamIDLobby)
	}

	log.info("Callback:", callback.iCallback)
}

create_lobby :: proc(ctx: ^SteamCtx) {
	_ = steam.Matchmaking_CreateLobby(ctx.matchmaking, .FriendsOnly, 4)
}
