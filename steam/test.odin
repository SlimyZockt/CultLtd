package steam

import "core:log"
import "core:net"
main :: proc() {
	context.logger = log.create_console_logger()

	log.debugf("%x", transmute(u32be)(net.IP4_Loopback))


}
