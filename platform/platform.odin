package platform

import steam "../vendor/steamworks/"
import "core:log"
import "core:math/rand"

Platform :: enum {
	Steam,
	Standalone,
	// StandaloneLinux64,
}

PlatformFeatures :: bit_set[PlatformFeaturesBits;u32]
PlatformFeaturesBits :: enum {
	Multiplayer,
	Achievements,
}
PlatformInfo :: struct {
	lobby_size:        u16,
	max_lobby_size:    u16,
	platform_features: PlatformFeatures,
	player_id:         PlayerId,
}

PlayerId :: distinct u64
Massage :: union {
	^steam.SteamNetworkingMessage,
}

NetEventReceive :: struct {
	msg: Massage,
}

NetEventCreated :: struct {}
NetEventConnectingToHost :: struct {
	id: PlayerId,
}
NetEventConnectedToHost :: struct {
	id: PlayerId,
}
NetEventPeerDisconnected :: struct {
	id: PlayerId,
}
NetEventPeerConnected :: struct {
	id: PlayerId,
}
NetEventDisconnectedFormHost :: struct {
	id: PlayerId,
}

NetEvent :: union {
	NetEventCreated,
	NetEventReceive,
	NetEventConnectedToHost,
	NetEventConnectingToHost,
	NetEventDisconnectedFormHost,
	NetEventPeerDisconnected,
	NetEventPeerConnected,
}

@(private)
platform := Platform.Standalone

PlatformCtx :: union {
	PlatformInfo,
	SteamCtx,
}

@(private)
ctx: PlatformCtx = nil
info: ^PlatformInfo = nil


platform_init :: proc($platform: Platform, log_level := log.Level.Debug) {
	context.logger = log.create_console_logger(log_level)
	switch platform {
	case .Steam:
		ctx = SteamCtx{}
		steam_init(&(ctx.(SteamCtx)))
		stem_ctx, ok := &(ctx.(SteamCtx))
		assert(ok)
		info = &steam_ctx.platform_info
	case .Standalone:
		STANDALONE_PLAYER_ID :: 77 // TODO: use something that makes sense
		ctx = PlatformInfo{}
		info = &(ctx.(PlatformInfo))
		info.player_id = STANDALONE_PLAYER_ID
	}
}

platform_update :: proc(
	network_event_callback: proc(data: NetEvent, user_data: rawptr),
	user_data: rawptr,
) {
	switch platform {
	case .Steam:
		steam_update_callback(&(ctx.(SteamCtx)), network_event_callback, user_data)
	case .Standalone:
	}
}

platform_disconnect_current_player_from_all :: proc() {
	switch platform {
	case .Steam:
		steam_disconnect_current_player_from_all(&(ctx.(SteamCtx)))
	case .Standalone:
	}
}

platform_send :: proc(data: ^$T, size: u32) {
	switch platform {
	case .Steam:
		steam_send(&(ctx.(SteamCtx)), data, size)
	case .Standalone:
	}
}

platform_create_lobby :: proc(max_lobby_size: u16 = 8) {
	switch platform {
	case .Steam:
		steam_create_lobby(&(ctx.(SteamCtx)), max_lobby_size)
	case .Standalone:
	}
}

platform_deinit :: proc() {
	switch platform {
	case .Steam:
		steam_deinit(&(ctx.(SteamCtx)))
	case .Standalone:
	}
}
