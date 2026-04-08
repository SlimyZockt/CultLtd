package game

import "core:container/xar"
import "core:log"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

update_logic :: proc(ctx: ^GameCtx, delta_time: f32) {
	if ctx.scene != .Game do return
	if .Host not_in ctx.flags do return

	for id, &player in ctx.players {
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

		if .Dash in player.input_down {
			defer player.input_pressed -= {.Dash}
			player_entity.velocity = {200, 200} * input
		}


	}


	for iter := xar.iterator(&ctx.entities.list); entity, i in xar.iterate_by_ptr(&iter) {
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

	for id, &player in ctx.players {
		player_entity, _ := entity_get(&ctx.entities, player.entity)

		if .PrimaryAction in player.input_down { 	// Shooting
			BULLET_SIZE :: 8
			defer player.input_pressed -= {.PrimaryAction}

			player_pos := player_entity.position + player_entity.size / 2 - BULLET_SIZE / 2
			target_pos := (player.mouse_position_world) - (BULLET_SIZE / 2)
			// log.debug(player.mouse_position_world)
			log.debug(id, player_entity.velocity)
			diff := target_pos - player_pos
			angle := math.atan2(diff.y, diff.x)
			direction := linalg.normalize(diff)

			entity_add_sync_server(
				ctx,
				Entity { 	// BULLET_ENTITY
					size      = BULLET_SIZE,
					speed     = 300,
					position  = target_pos,
					velocity  = direction * 300,
					friction  = 100,
					angle     = angle,
					ttl       = 1.5,
					direction = direction,
					// texture_id = .Bullet,
					flags     = {.Sync, .Alive, .TTL, .DestroyOnVelocityStop},
				},
			)
		}
	}
}
