package game

import "core:container/xar"
import "core:math"
import "core:math/linalg"

update_logic :: proc(ctx: ^CultCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	if .Server not_in ctx.flags do return

	for _, &player in ctx.players {
		entity, _ := entity_get(&ctx.entities, player.entity)
		input: [2]f32

		input_down := player.input_down
		if .Up in input_down do input.y -= 1
		if .Down in input_down do input.y += 1
		if .Right in input_down do input.x += 1
		if .Left in input_down do input.x -= 1

		if input.x != 0 || input.y != 0 {
			dir := linalg.normalize(input)
			entity.position += dir * entity.speed * delta_time
		}

		if .PrimaryAction in player.input_pressed { 	// Shooting
			defer player.input_pressed -= {.PrimaryAction}
			diff := player.mouse_position_world - entity.position
			angle := math.atan2(diff.y, diff.x)
			direction := [2]f32{math.cos(angle), math.sin(angle)}
			entity_add_sync_server(
				ctx,
				Entity {
					size = {16, 16},
					speed = 300,
					position = entity.position,
					velocity = direction * 300,
					friction = 100,
					angle = angle,
					ttl = 1,
					direction = direction,
					flags = {.Sync, .Physics, .Alive, .TTL},
				},
			)
		}

		if .Dash in player.input_pressed { 	// Shooting
			defer player.input_pressed -= {.Dash}
			entity.velocity = {200, 200} * input
		}
	}

	entity_iter := xar.iterator(&ctx.entities.list)
	for entity in xar.iterate_by_ptr(&entity_iter) {
		i := u64(entity_iter.idx) - 1
		if .Physics in entity.flags {
			if entity.velocity != {0, 0} {
				entity.position += entity.velocity * delta_time

				speed := linalg.length(entity.velocity)
				new_speed := max(f32(0), speed - entity.friction * delta_time)
				if new_speed == 0 {
					entity.velocity = [2]f32{0, 0}
				} else {
					entity.velocity = linalg.normalize(entity.velocity) * new_speed
				}
			}
		}

		if .TTL in entity.flags {
			if entity.ttl <= 0 {
				entity_delete_sync_server(&ctx.entities, EntityHandle{i, entity.generation})
			} else {
				entity.ttl -= Seconds(delta_time)
			}
		}
	}
}
