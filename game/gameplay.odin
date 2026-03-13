package game

import "core:container/xar"
import "core:log"
import "core:math"
import "core:math/linalg"

update_logic :: proc(ctx: ^GameCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	if .Host not_in ctx.flags do return

	for _, &player in ctx.players {
		player_entity, _ := entity_get(&ctx.entities, player.entity)
		input: Vec2

		input_down := player.input_down
		if .Up in input_down do input.y -= 1
		if .Down in input_down do input.y += 1
		if .Right in input_down do input.x += 1
		if .Left in input_down do input.x -= 1

		if input.x != 0 || input.y != 0 {
			dir := linalg.normalize(input)
			player_entity.velocity = dir * player_entity.speed
		}

		if .PrimaryAction in player.input_pressed { 	// Shooting
			defer player.input_pressed -= {.PrimaryAction}
			diff := player.mouse_position_world - player_entity.position
			angle := math.atan2(diff.y, diff.x)
			direction := Vec2{math.cos(angle), math.sin(angle)}
			entity_add_sync_server(
				ctx,
				Entity {
					size = {16, 16},
					speed = 300,
					position = player_entity.position,
					velocity = direction * 600 + player_entity.velocity,
					friction = 100,
					angle = angle,
					ttl = 1.5,
					direction = direction,
					flags = {.Sync, .Velocity, .Alive, .TTL, .DestroyOnVelocityStop},
				},
			)
		}

		if .Dash in player.input_pressed { 	// Shooting
			defer player.input_pressed -= {.Dash}
			player_entity.velocity = {200, 200} * input
		}
	}

	entity_iter := xar.iterator(&ctx.entities.list)
	for entity, i in xar.iterate_by_ptr(&entity_iter) {
		if .Alive not_in entity.flags do continue
		if .Velocity in entity.flags {
			if entity.velocity != {0, 0} {
				entity.position += entity.velocity * delta_time

				speed := linalg.length(entity.velocity)
				new_speed := max(f32(0), speed - entity.friction * delta_time)
				if new_speed == 0 {
					entity.velocity = Vec2{0, 0}
				} else {
					entity.velocity = linalg.normalize(entity.velocity) * new_speed
				}
			}
		}

		if .DestroyOnVelocityStop in entity.flags {
			if entity.velocity == {0, 0} {
				entity_delete_sync_server(ctx, EntityHandle{u64(i), entity.generation})
			}
		}

		if .TTL in entity.flags {
			if entity.ttl <= 0 {
				entity_delete_sync_server(ctx, EntityHandle{u64(i), entity.generation})
			}
			entity.ttl -= Seconds(delta_time)
		}
	}
}
