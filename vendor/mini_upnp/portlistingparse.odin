/* $Id: portlistingparse.h,v 1.12 2025/02/08 23:15:17 nanard Exp $ */
/* MiniUPnP project
 * http://miniupnp.free.fr/ or http://miniupnp.tuxfamily.org/
 * (c) 2011-2025 Thomas Bernard
 * This software is subject to the conditions detailed
 * in the LICENCE file provided within the distribution */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"upnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"upnpc.lib"}
}


/*!
* \brief enum of all XML elements
*/
Port_Mapping_Elt :: enum u32 {
	/*!
	* \brief enum of all XML elements
	*/
	PortMappingEltNone = 0,
	PortMappingEntry   = 1,
	NewRemoteHost      = 2,
	NewExternalPort    = 3,
	NewProtocol        = 4,
	NewInternalPort    = 5,
	NewInternalClient  = 6,
	NewEnabled         = 7,
	NewDescription     = 8,
	NewLeaseTime       = 9,
}

/*!
* \brief linked list of port mappings
*/
Port_Mapping :: struct {
	l_next:         ^Port_Mapping, /*!< \brief next list element */
	leaseTime:      u64,           /*!< \brief in seconds */
	externalPort:   u16,           /*!< \brief external port */
	internalPort:   u16,           /*!< \brief internal port */
	remoteHost:     [64]i8,        /*!< \brief empty for wildcard */
	internalClient: [64]i8,        /*!< \brief internal IP address */
	description:    [64]i8,        /*!< \brief description */
	protocol:       [4]i8,         /*!< \brief `TCP` or `UDP` */
	enabled:        u8,            /*!< \brief 0 (false) or 1 (true) */
}

/*!
* \brief structure for ParsePortListing()
*/
Port_Mapping_Parser_Data :: struct {
	l_head: ^Port_Mapping,    /*!< \brief list head */
	curelt: Port_Mapping_Elt, /*!< \brief currently parsed element */
}

@(default_calling_convention="c", link_prefix="upnp")
foreign lib {
	/*!
	* \brief parse the NewPortListing part of GetListOfPortMappings response
	*
	* \param[in] buffer XML data
	* \param[in] bufsize length of XML data
	* \param[out] pdata Parsed data
	*/
	ParsePortListing :: proc(buffer: cstring, bufsize: i32, pdata: ^Port_Mapping_Parser_Data) ---

	/*!
	* \brief free parsed data structure
	*
	* \param[in] pdata Parsed data to free
	*/
	FreePortListing :: proc(pdata: ^Port_Mapping_Parser_Data) ---
}

