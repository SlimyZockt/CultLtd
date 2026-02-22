package game

import steam "../steam/"
import steamworks "../vendor/steamworks/"
import "core:container/queue"
import "core:container/xar"
import "core:log"
import vmem "core:mem/virtual"

update_network_steam :: proc(ctx: ^CultCtx) {
	on_receive_msg :: proc(msg: ^steamworks.SteamNetworkingMessage, user_data: rawptr) {
		ctx := (^CultCtx)(user_data)
		header := (^NetworkMsgHeader)(msg.pData)

		switch header.type {
		case .ServerSnapshot:
			assert(.Server not_in ctx.flags)
			data := (^NetworkServerSnapshot)(msg.pData)
			assert(data.entity_count <= MAX_ENTITY_SYNC_COUNT)
			for i in 0 ..< min(data.entity_count, MAX_ENTITY_SYNC_COUNT) {
				entity_data := data.entities[i]

				handle, exists := ctx.network_id_to_handle_client[entity_data.network_id]
				if !exists {
					if .Destroy in entity_data.flags do continue
					new_handle := entity_add(&ctx.entities, Entity{net = entity_data})
					ctx.network_id_to_handle_client[entity_data.network_id] = new_handle

					if pending, ok := ctx.pending_player_assignment.?;
					   ok && pending == entity_data.network_id {
						ctx.players[ctx.player_id] = {
							entity = new_handle,
						}
						ctx.pending_player_assignment = nil
					}
					continue
				}

				if .Destroy in entity_data.flags {
					entity_delete(&ctx.entities, handle)
					delete_key(&ctx.network_id_to_handle_client, entity_data.network_id)
					continue
				}

				entity, ok := entity_get(&ctx.entities, handle)
				if !ok {
					delete_key(&ctx.network_id_to_handle_client, entity_data.network_id)
					continue
				}

				entity.net = entity_data

				continue
			}

		case .ClientInput:
			assert(.Server in ctx.flags)
			data := (^NetworkClientInput)(msg.pData)
			player, ok := ctx.players[data.id]
			if !ok do return
			player.network_shared_data = data.player
			ctx.players[data.id] = player

		case .PlayerAssignment:
			assert(.Server not_in ctx.flags)
			data := (^NetworkPlayerAssignment)(msg.pData)
			if data.target_player_id == ctx.player_id {
				handle, exists := ctx.network_id_to_handle_client[data.entity_network_id]
				if exists {
					ctx.players[ctx.player_id] = {
						entity = handle,
					}
				} else {
					ctx.pending_player_assignment = data.entity_network_id
				}
			}
		}
	}

	for ctx.steam.event_queue.len > 0 {
		event := queue.pop_front(&ctx.steam.event_queue)
		log.debug(event)
		switch event.type {
		case .ConnectingToHost:
			ctx.scene = .Loading
		case .Created:
			ctx.flags += {.Server}
			allocator := vmem.arena_allocator(&g_arena)
			game_enter(ctx, allocator, true)
		case .ConnectedToHost:
			allocator := vmem.arena_allocator(&g_arena)
			game_enter(ctx, allocator, true)
		case .PeerDisconnected:
			peer_handle := ctx.players[PlayerId(event.id)].entity
			peer_entity, _ := entity_get(&ctx.entities, peer_handle)
			peer_entity.flags += {.Destroy}
			peer_entity.flags -= {.Alive}
		case .PeerConnected:
			ctx.player_count += 1
			entity := PLAYER_ENTITY
			new_handle := entity_add_sync_server(ctx, entity)
			ctx.players[PlayerId(event.id)] = {
				entity = new_handle,
			}
			new_entity, _ := entity_get(&ctx.entities, new_handle)
			assignment := NetworkPlayerAssignment {
				type              = .PlayerAssignment,
				target_player_id  = PlayerId(event.id),
				entity_network_id = new_entity.network_id,
			}
			steam.write(&ctx.steam, &assignment, size_of(assignment))
		case .DisconnectedFormHost:
			game_exit(ctx)
		}
	}

	if ctx.scene != .Game do return
	steam.process_received_msg(ctx.steam, on_receive_msg, ctx)

	if .Server in ctx.flags {
		packet := NetworkServerSnapshot {
			type = .ServerSnapshot,
		}
		iter := xar.iterator(&ctx.entities.list)
		for entity in xar.iterate_by_ptr(&iter) {
			i := u64(iter.idx) - 1
			if .Sync in entity.flags {
				packet.entities[packet.entity_count] = entity
				packet.entity_count += 1
			}

			if packet.entity_count == MAX_ENTITY_SYNC_COUNT {
				steam.write(&ctx.steam, &packet, size_of(packet))
				packet = NetworkServerSnapshot {
					type = .ServerSnapshot,
				}
			}

			if entity.flags >= {.Destroy, .Sync} {
				entity.flags -= {.Destroy, .Sync}
				entity_delete(&ctx.entities, EntityHandle{u64(i), entity.generation})
			}
		}

		if packet.entity_count > 0 {
			steam.write(&ctx.steam, &packet, size_of(packet))
		}
	}

	if .Server not_in ctx.flags {
		player := ctx.players[ctx.player_id]
		packet := NetworkClientInput {
			type   = .ClientInput,
			id     = ctx.player_id,
			player = player.network_shared_data,
		}
		steam.write(&ctx.steam, &packet, size_of(packet))

		player.input_pressed = {}
		ctx.players[ctx.player_id] = player
	}
}
