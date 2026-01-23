/* $Id: miniwget.h,v 1.15 2025/03/02 01:14:38 nanard Exp $ */
/* Project : miniupnp
 * Author : Thomas Bernard
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * Copyright (c) 2005-2025 Thomas Bernard
 * This software is subject to the conditions detailed in the
 * LICENCE file provided in this distribution.
 * */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"libminiupnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"libminiupnpc.lib"}
}


@(default_calling_convention="c")
foreign lib {
	/*! \brief perform HTTP GET on an URL
	*
	* \param[in] url HTTP URL to GET
	* \param[out] size length of the returned buffer. -1 in case of memory
	*             allocation error
	* \param[in] scope_id interface id for IPv6 to use if not specified in the URL
	* \param[out] status_code HTTP response status code (200, 404, etc.)
	* \return the body of the HTTP response
	*/
	miniwget :: proc(url: cstring, size: ^i32, scope_id: u32, status_code: ^i32) -> rawptr ---

	/*! \brief perform HTTP GET on an URL
	*
	* Also get the local address used to reach the HTTP server
	*
	* \param[in] url HTTP URL to GET
	* \param[out] size length of the returned buffer. -1 in case of memory
	*             allocation error
	* \param[out] addr local address used to connect to the server
	* \param[in] addrlen size of the addr buffer
	* \param[in] scope_id interface id for IPv6 to use if not specified in the URL
	* \param[out] status_code HTTP response status code (200, 404, etc.)
	* \return the body of the HTTP response
	*/
	miniwget_getaddr :: proc(url: cstring, size: ^i32, addr: cstring, addrlen: i32, scope_id: u32, status_code: ^i32) -> rawptr ---
}

