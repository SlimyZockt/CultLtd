package main

import mupnp "./vendor/mini_upnp"
import "core:log"
import "vendor:ENet"

NetFlagBits :: enum u32 {
	Initilazed,
}
NetFlags :: bit_set[NetFlagBits;u32]

NET_CHANNEL_COUNT :: 2
MAX_PLAYER_COUNT :: 8

NetCtx :: struct {
	flags:       NetFlags,
	host:        ^ENet.Host,
	peer_server: ^ENet.Peer,
	peers:       []^ENet.Peer,
	peer_count:  u64,
	// max_peer_count: u64,
	is_server:   bool,
	address:     ENet.Address,
}

NetData :: struct {
	stuff: string,
}

net_init :: proc(ctx: ^NetCtx, port: u16 = 7777) {
	ok := ENet.initialize()
	assert(ok == 0) //FIXME(abdul): proper err handling
	if ok != 0 {
		log.error("An error occurred while initializing")
	}
	ctx.address.host = ENet.HOST_ANY
	ctx.address.port = port
	ctx.peers = make([]^ENet.Peer, MAX_PLAYER_COUNT)
}

net_create_server :: proc(ctx: ^NetCtx) {
	assert(ctx.address.host == ENet.HOST_ANY)
	ctx.host = ENet.host_create(&ctx.address, MAX_PLAYER_COUNT, NET_CHANNEL_COUNT, 0, 0)
	assert(ctx.host != nil) //FIXME(abdul): proper err handling
}

net_create_client :: proc(ctx: ^NetCtx) {
	ctx.host = ENet.host_create(nil, 1, NET_CHANNEL_COUNT, 0, 0)
	assert(ctx.host != nil) //FIXME(abdul): proper err handling
}

net_deinit :: proc() {
	ENet.deinitialize()
}

net_update :: proc(ctx: ^CultCtx) {
	if ctx.net.host == nil do return
	event: ENet.Event
	for ENet.host_service(ctx.net.host, &event, 0) > 0 {

		switch event.type {
		case .CONNECT:
			log.infof(
				"Client connected form %v:%v: with %v",
				event.peer.address.host,
				event.peer.address.port,
				(^NetData)(event.peer.data),
			)

			data := (^NetData)(event.peer.data)

			game_init(ctx, MAX_PLAYER_COUNT)
			net_write(&ctx.net, {})
			for i in 0 ..< ctx.steam.lobby_size {
				player := &ctx.players[i]
				player.id = u64(i)
			}

			event.peer.data = nil //TODO(abdul) set data
		case .DISCONNECT:
			defer event.peer.data = nil
			log.infof("Client disconnected:  %v", event.peer.data)
		case .RECEIVE:
			log.infof(
				"A packet of length %u containing %s was received from %s on channel %u.\n",
				event.packet.dataLength,
				event.packet.data,
				(^NetData)(event.peer.data),
				event.channelID,
			)
			defer ENet.packet_destroy(event.packet)
		case .NONE:
		}

	}
}

net_write :: proc(ctx: ^NetCtx, data: NetData) {
	// packet := ENet.packet_create(data, size_of(NetData), {.RELIABLE})
	msg := "hello form someone"
	packet := ENet.packet_create(&msg, len(msg), {.RELIABLE})
	ENet.peer_send(ctx.peer_server, 0, packet)
}


net_disconnect :: proc(ctx: NetCtx, id: u64) {
	ENet.host_destroy(ctx.host)
	// _ = id
	// ENet.peer_disconnect(nil, 0)
}

net_disconnect_all :: proc() {}

NetConnectionData :: struct {
	id: u8,
	_:  u8,
	_:  u8,
	_:  u8,
}
#assert(size_of(NetConnectionData) == 4)

net_connect :: proc(ctx: ^CultCtx, address: u32 = 0x7f000001) {
	ctx.net.address.host = address

	ctx.net.peer_count += 1
	assert(ctx.net.peers != nil)
	ctx.net.peers[ctx.net.peer_count] = ENet.host_connect(
		ctx.net.host,
		&ctx.net.address,
		NET_CHANNEL_COUNT,
		0,
	)

	assert(ctx.net.peers[ctx.net.peer_count] != nil)
}
