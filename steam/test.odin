package steam

import "core:log"
import "core:net"
main :: proc() {
	context.logger = log.create_console_logger()

	log.debugf("%x", transmute(u32)(net.IP4_Loopback))


	NetConnectionData :: struct {
		id: u8,
		_:  u8,
		_:  u8,
		_:  u8,
	}
	log.info(size_of(NetConnectionData))
}
