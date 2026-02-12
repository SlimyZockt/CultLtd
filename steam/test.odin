package steam

import "core:log"
import "core:mem"
import "core:net"


Test :: union {
	struct {
		a: u64,
	},
	struct {
		b: u128,
	},
}

main :: proc() {
	context.logger = log.create_console_logger()

	b: Test
	b = (struct {
			a: u64,
		}) {
		a = u64(4),
	}

	a := mem.any_to_bytes(&b)

	log.debugf("%v", b)
	log.debugf("%v", a)
	c := cast(^Test)(&a)
	log.debugf("%v", c)


}
