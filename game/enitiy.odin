package game

import "core:container/xar"
import "core:log"

entity_add_sync_server :: proc(ctx: ^GameCtx, entity: Entity) -> EntityHandle {
	entity := entity
	assert(.Sync in entity.flags)
	assert(.Server in ctx.flags)
	entity.network_id = ctx.network_next_id_server
	ctx.network_next_id_server += 1
	// entity.owner_id =
	return entity_add(&ctx.entities, entity)
}

entity_add :: proc(entities: ^EntityList, entity: Entity) -> EntityHandle {
	if idx, ok := entities.FreeEntityIdx.?; ok {
		new_entity := xar.get_ptr(&entities.list, idx)
		generation := new_entity.generation
		entities.FreeEntityIdx = new_entity.NextFreeEntityIdx

		new_entity^ = entity
		new_entity.NextFreeEntityIdx = nil
		new_entity.generation = generation

		return EntityHandle{idx, generation}
	}


	assert(entity.generation == 0)
	assert(entity.NextFreeEntityIdx == nil)
	xar.append(&entities.list, entity)

	idx := entities.list.len - 1
	return EntityHandle{u64(idx), 0}
}

entity_delete_sync_server :: proc(entities: ^EntityList, entity_handle: EntityHandle) {
	entity, ok := entity_get(entities, entity_handle)
	assert(.Sync in entity.flags)
	if !ok {
		log.errorf("try to delete sync an not existing element %v", entity_handle)
		return
	}

	entity.flags += {.Destroy}
}

entity_delete :: proc(entities: ^EntityList, entity_handle: EntityHandle) {
	entity := xar.get_ptr(&entities.list, entity_handle.id)
	if entity.generation != entity_handle.generation {
		log.errorf("try to delete an not existing element %v", entity_handle)
		return
	}

	generation := entity.generation + 1
	entity^ = {
		generation        = generation,
		NextFreeEntityIdx = entities.FreeEntityIdx,
	}
	entities.FreeEntityIdx = entity_handle.id

	log.infof("Entity %v deleted", entity_handle)
}


entity_get :: proc(entities: ^EntityList, entity_handle: EntityHandle) -> (^Entity, bool) {
	@(static) entity_stub: Entity

	if int(entity_handle.id) >= entities.list.len do return &entity_stub, false
	entity := xar.get_ptr(&entities.list, entity_handle.id)
	if entity.generation != entity_handle.generation {
		log.error("Wrong generation entity")
		return &entity_stub, false
	}

	return entity, true
}
