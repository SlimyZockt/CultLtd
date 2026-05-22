package steam

import "core:log"
import "core:mem"

Test :: union {
	struct {
		a: u64,
	},
	struct {
		b: u128,
	},
}

T1 :: struct {
	// a: u16,
	// a: u32,
	c: u32,
	b: u64,
	a: u32,
	d: u64,
}

T2 :: struct {
	c: u32,
	a: u32,
	b: u64,
	// a: u16,
	d: u64,
}

T3 :: struct {
	d: u64,
	c: u32,
	// a: u16,
	a: u32,
	b: u64,
}

ENTITY_ZERO: u32

main :: proc() {
	context.logger = log.create_console_logger()

	b: Test
	b = (struct {
			a: u64,
		}) {
		a = u64(4),
	}

	a := mem.any_to_bytes(&b)

	j := 0
	for i in 0 ..< 10 {
		defer {
			j += 1
			log.debug(j)
		}

		if i == 5 do continue
	}

	e := &ENTITY_ZERO

	e^ = 32

	log.debugf("%v", b)
	log.debugf("%v", a)

	log.debugf("%v", size_of(T1))
	log.debugf("%v", size_of(T2))
	log.debugf("%v", size_of(T3))
}
