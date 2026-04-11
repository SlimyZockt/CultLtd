package game

import "core:container/xar"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

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

		// if input.x != 0 || input.y != 0 {
		// }

		dir := linalg.normalize(input)
		player_entity.direction = dir
		player_entity.flags += {.Moving}


		if .Dash in player.input_pressed {
			player.input_pressed -= {.Dash}
			if .IsDashing not_in player.state {
				// continue
				player.state += {.IsDashing}
				player_entity.velocity = dir * player_entity.speed * 2
				player_entity.friction = 1000

				for _ in 0 ..< rand.uint32_range(8, 15) {
					pos := Vec2 {
						player_entity.position.x +
						rand.float32_range(-player_entity.size.x / 2, player_entity.size.x / 2),
						player_entity.position.y +
						rand.float32_range(-player_entity.size.y / 2, player_entity.size.y / 2),
					}
					entity_add_sync_server(
						ctx,
						Entity { 	// "Particles"
							size      = 3,
							speed     = 300,
							position  = pos,
							velocity  = -player_entity.velocity / 2,
							friction  = 100,
							angle     = 0,
							ttl       = .100,
							direction = 0,
							tint      = Color{0xe4, 0x3b, 0x44, 0xF0},
							flags     = {.Sync, .Velocity, .Alive, .TTL, .DestroyOnVelocityStop},
						},
					)
				}
			}
		}

		DASH_STOP_SPEED :: 380
		speed := linalg.length(player_entity.velocity)
		if .IsDashing in player.state && max(speed, DASH_STOP_SPEED) == DASH_STOP_SPEED {
			player_entity.velocity = 0
			player_entity.friction = math.F32_MAX
			player.state -= {.IsDashing}
			// log.debug("undahsing")
		}

		if input == 0 {
			player_entity.flags -= {.Moving}
		} else if .IsDashing not_in player.state {
			log.debug(dir, player_entity.speed)
			player_entity.velocity = dir * player_entity.speed
			log.debug(player_entity.velocity)
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

	local_player, ok := ctx.players[ctx.player_id]
	assert(ok)
	local_player_entity, _ := entity_get(&ctx.entities, local_player.entity)
	if local_player_entity != nil && .Alive in local_player_entity.flags {
		ctx.camera.target = local_player_entity.position
	}

	for _, &player in ctx.players {
		player_entity, _ := entity_get(&ctx.entities, player.entity)
		// assert(ok)

		if .PrimaryAction in player.input_pressed { 	// Shooting
			defer player.input_pressed -= {.PrimaryAction}
			BULLET_SIZE :: 8
			mouse_position_world := rl.GetScreenToWorld2D(
				player.mouse_virtual_screen_position,
				ctx.camera,
			)

			player_pos := player_entity.position
			target_pos := mouse_position_world
			diff := target_pos - player_pos
			angle := math.atan2(diff.y, diff.x)
			direction := linalg.normalize(diff)

			entity_add_sync_server(
				ctx,
				Entity { 	// BULLET_ENTITY
					size      = BULLET_SIZE,
					speed     = 300,
					position  = player_pos,
					velocity  = direction * (player_entity.speed + 300),
					friction  = 100,
					angle     = angle,
					ttl       = 1.5,
					direction = direction,
					// texture_id = .Bullet,
					flags     = {.Sync, .Velocity, .Alive, .TTL, .DestroyOnVelocityStop},
					tint      = GHOST_COLOR,
				},
			)
		}
	}
}
