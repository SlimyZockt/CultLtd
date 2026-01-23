/* $Id: upnperrors.h,v 1.8 2025/02/08 23:15:17 nanard Exp $ */
/* (c) 2007-2025 Thomas Bernard
 * All rights reserved.
 * MiniUPnP Project.
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * This software is subjet to the conditions detailed in the
 * provided LICENCE file. */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"libminiupnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"libminiupnpc.lib"}
}


@(default_calling_convention="c")
foreign lib {
	/*!
	* \brief convert error code to string
	*
	* Work for both MiniUPnPc specific errors and UPnP standard defined
	* errors.
	*
	* \param[in] err numerical error code
	* \return a string description of the error code
	*         or NULL for undefinded errors
	*/
	strupnperror :: proc(err: i32) -> cstring ---
}

