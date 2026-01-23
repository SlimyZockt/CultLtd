/* $Id: upnpdev.h,v 1.6 2025/02/08 23:15:17 nanard Exp $ */
/* Project : miniupnp
 * Web : http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * Author : Thomas BERNARD
 * copyright (c) 2005-2025 Thomas Bernard
 * This software is subjet to the conditions detailed in the
 * provided LICENSE file. */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib "libminiupnpc.a"
} else when ODIN_OS == .Windows {
	foreign import lib "libminiupnpc.lib"
}


/*!
* \brief UPnP device linked-list
*/
Dev :: struct {
	/*! \brief pointer to the next element */
	pNext:    ^Dev,

	/*! \brief root description URL */
	descURL:  cstring,

	/*! \brief ST: as advertised */
	st:       cstring,

	/*! \brief USN: as advertised */
	usn:      cstring,

	/*! \brief IPv6 scope id of the network interface */
	scope_id: u32,

	/* C99 flexible array member */
	/*! \brief buffer for descURL, st and usn */
	buffer:   [^]i8,
}

@(default_calling_convention = "c")
foreign lib {
	/*! \brief free list returned by upnpDiscover()
	* \param[in] devlist linked list to free
	*/
	freeUPNPDevlist :: proc(devlist: ^Dev) ---
}
