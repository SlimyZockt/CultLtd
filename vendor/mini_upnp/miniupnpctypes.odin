/* $Id: miniupnpctypes.h,v 1.5 2025/03/02 01:15:44 nanard Exp $ */
/* Project: miniupnp
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org
 * Author: Thomas Bernard
 * Copyright (c) 2021-2025 Thomas Bernard
 * This software is subject to the conditions detailed in the
 * LICENCE file provided within this distribution */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"upnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"upnpc.lib"}
}


