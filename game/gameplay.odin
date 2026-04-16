package game

import "core:container/xar"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

GunTypes :: enum u16 {
	SingleShoot,
	RandSpreedShoot,
	SpreedShoot,
}

// GunAttributes :: enum u16 {
// 	BulletsPerShoot,
// 	Recoil,
// 	FireRate,
// 	BulletLifetime,
// 	BulletDamage,
// 	BulletSpeed,
// 	BulletFriction,
// }

// GunAttributFlag :: bit_set[GunAttributes;u16]

GunSpreadType :: enum u8 {
	None,
	Random,
	Even,
}

GunData :: struct {
	bullets_per_shoot:  u8,
	spread_type:        GunSpreadType,
	spread_size:        f16,
	fire_rate:          f16,
	recoil:             u16,
	bullet_lifetime:    f16,
	bullet_speed:       u16,
	bullet_friction:    u16,
	base_bullet_damage: u16,
}


@(rodata)
GUNS := [GunTypes]GunData {
	.SingleShoot = {
		bullets_per_shoot = 1,
		recoil = 0,
		spread_type = .None,
		spread_size = 0,
		fire_rate = 0,
		bullet_lifetime = 1.5,
		bullet_speed = u16(PLAYER_ENTITY.speed) + 200,
		bullet_friction = 200,
		base_bullet_damage = 100,
	},
	.RandSpreedShoot = {
		bullets_per_shoot = 10,
		recoil = 5,
		spread_type = .Random,
		spread_size = math.PI,
		fire_rate = 10,
		bullet_lifetime = 1.5,
		bullet_speed = u16(PLAYER_ENTITY.speed) + 200,
		bullet_friction = 200,
		base_bullet_damage = 100,
	},
	.SpreedShoot = {
		bullets_per_shoot = 10,
		recoil = 300,
		spread_type = .Even,
		spread_size = math.PI,
		fire_rate = 10,
		bullet_lifetime = 1.5,
		bullet_speed = u16(PLAYER_ENTITY.speed) + 200,
		bullet_friction = 200,
		base_bullet_damage = 100,
	},
}

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

		dir := linalg.normalize(input)
		player_entity.direction = dir

		if .Dash in player.input_pressed {
			player.input_pressed -= {.Dash}
			if .IsDashing not_in player.state {
				// continue
				player.state += {.IsDashing}
				player_entity.velocity = dir * 600
				// player_entity.friction = 2000

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
							// angle     = 0,
							ttl_in_s  = .100,
							direction = 0,
							tint      = Color{0xe4, 0x3b, 0x44, 0xF0}, // #e43b44_F0
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
			// player_entity.friction = math.F32_MAX
			player.state -= {.IsDashing}
		}

		if input == 0 {
			player_entity.flags -= {.Moving}
		} else {
			player_entity.flags += {.Moving}
			if .IsDashing not_in player.state {
				player_entity.position += dir * player_entity.speed * delta_time
			}
		}

		if .PrimaryAction in player.input_pressed { 	// Shooting
			defer player.input_pressed -= {.PrimaryAction}
			BULLET_SIZE :: 8
			mouse_position_world := rl.GetScreenToWorld2D(
				player.mouse_virtual_screen_position,
				ctx.camera,
			)

			diff := mouse_position_world - player_entity.position
			angle := math.atan2(diff.y, diff.x)
			direction := linalg.normalize(diff)

			gun := GUNS[.SpreedShoot]

			player_entity.velocity -= direction * f32(gun.recoil)

			gun_index_offset: f32
			gun_radiant_per_bullet: f32
			if gun.spread_type == .Even { 	// offset for even spreed type
				gun_index_offset = f32(gun.bullets_per_shoot) / 2
				gun_radiant_per_bullet = f32(gun.spread_size) / f32(gun.bullets_per_shoot)
			}

			for i in 0 ..< gun.bullets_per_shoot {
				tmp := f32(gun.spread_size) / 2
				spreed_angle := angle
				switch gun.spread_type {
				case .None:
				case .Random:
					spreed_angle -= rand.float32_uniform(-tmp, tmp)
				case .Even:
					spreed_angle -= (f32(i) - gun_index_offset) * gun_radiant_per_bullet
				}
				rot := Vec2{math.cos(spreed_angle), math.sin(spreed_angle)}
				entity_add_sync_server(
					ctx,
					Entity { 	// BULLET_ENTITY
						size      = BULLET_SIZE,
						speed     = f32(gun.bullet_speed),
						position  = player_entity^.position,
						velocity  = (rot) * (player_entity.speed + f32(gun.bullet_speed)),
						friction  = f32(gun.bullet_friction),
						// angle     = angle,
						ttl_in_s  = f32(gun.bullet_lifetime),
						direction = direction,
						flags     = {.Sync, .Velocity, .Alive, .TTL, .DestroyOnVelocityStop},
						tint      = GHOST_COLOR,
					},
				)
			}
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
			if entity.ttl_in_s <= 0 {
				entity_delete_sync_server(ctx, EntityHandle{u64(i), entity.generation})
			}
			entity.ttl_in_s -= delta_time
		}
	}

	local_player, ok := ctx.players[ctx.player_id]
	assert(ok)
	local_player_entity, _ := entity_get(&ctx.entities, local_player.entity)
	if local_player_entity != nil && .Alive in local_player_entity.flags {
		ctx.camera.target = local_player_entity.position
	}

	// for _, &player in ctx.players {
	// 	// player_entity, _ := entity_get(&ctx.entities, player.entity)
	// 	// assert(ok)
	//
	// }
}
