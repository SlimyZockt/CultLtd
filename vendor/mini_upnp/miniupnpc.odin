/* $Id: miniupnpc.h,v 1.79 2025/05/25 21:51:11 nanard Exp $ */
/* vim: tabstop=4 shiftwidth=4 noexpandtab
 * Project: miniupnp
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * Author: Thomas Bernard
 * Copyright (c) 2005-2025 Thomas Bernard
 * This software is subjects to the conditions detailed
 * in the LICENCE file provided within this distribution */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"libminiupnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"libminiupnpc.lib"}
}


/* error codes : */
/*! \brief value for success */
UPNPDISCOVER_SUCCESS :: (0)

/*! \brief value for unknown error */
UPNPDISCOVER_UNKNOWN_ERROR :: (-1)

/*! \brief value for a socket error */
UPNPDISCOVER_SOCKET_ERROR :: (-101)

/*! \brief value for a memory allocation error */
UPNPDISCOVER_MEMORY_ERROR :: (-102)

/*! \brief software version */
MINIUPNPC_VERSION :: "2.3.3"

/*! \brief C API version */
MINIUPNPC_API_VERSION :: 21

/*! \brief any (ie system chosen) port */
LOCAL_PORT_ANY     :: 0

/*! \brief Use as an alias for 1900 for backwards compatibility */
LOCAL_PORT_SAME    :: 1

/*!
* \brief UPnP method argument
*/
Arg :: struct {
	elt: cstring, /*!< \brief UPnP argument name */
	val: cstring, /*!< \brief UPnP argument value */
}

@(default_calling_convention="c")
foreign lib {
	/*!
	* \brief execute a UPnP method (SOAP action)
	*
	* \todo error reporting should be improved
	*
	* \param[in] url Control URL for the service
	* \param[in] service service to use
	* \param[in] action action to call
	* \param[in] args action arguments
	* \param[out] bufsize the size of the returned buffer
	* \return NULL in case of error or the raw XML response
	*/
	simpleUPnPcommand :: proc(url: cstring, service: cstring, action: cstring, args: ^Arg, bufsize: ^i32) -> cstring ---

	/*!
	* \brief Discover UPnP IGD on the network.
	*
	* The discovered devices are returned as a chained list.
	* It is up to the caller to free the list with freeUPNPDevlist().
	* If available, device list will be obtained from MiniSSDPd.
	*
	* \param[in] delay (in millisecond) maximum time for waiting any device
	*            response
	* \param[in] multicastif If not NULL, used instead of the default
	*            multicast interface for sending SSDP discover packets
	* \param[in] minissdpdsock Path to minissdpd socket, default is used if
	*            NULL
	* \param[in] localport Source port to send SSDP packets.
	*            #UPNP_LOCAL_PORT_SAME for 1900 (same as destination port)
	*            #UPNP_LOCAL_PORT_ANY to let system assign a source port
	* \param[in] ipv6 0 for IPv4, 1 of IPv6
	* \param[in] ttl should default to 2 as advised by UDA 1.1
	* \param[out] error error code when NULL is returned
	* \return NULL or a linked list
	*/
	upnpDiscover :: proc(delay: i32, multicastif: cstring, minissdpdsock: cstring, localport: i32, ipv6: i32, ttl: u8, error: ^i32) -> ^Dev ---

	/*!
	* \brief Discover all UPnP devices on the network
	*
	* search for "ssdp:all"
	* \param[in] delay (in millisecond) maximum time for waiting any device
	*            response
	* \param[in] multicastif If not NULL, used instead of the default
	*            multicast interface for sending SSDP discover packets
	* \param[in] minissdpdsock Path to minissdpd socket, default is used if
	*            NULL
	* \param[in] localport Source port to send SSDP packets.
	*            #UPNP_LOCAL_PORT_SAME for 1900 (same as destination port)
	*            #UPNP_LOCAL_PORT_ANY to let system assign a source port
	* \param[in] ipv6 0 for IPv4, 1 of IPv6
	* \param[in] ttl should default to 2 as advised by UDA 1.1
	* \param[out] error error code when NULL is returned
	* \return NULL or a linked list
	*/
	upnpDiscoverAll :: proc(delay: i32, multicastif: cstring, minissdpdsock: cstring, localport: i32, ipv6: i32, ttl: u8, error: ^i32) -> ^Dev ---

	/*!
	* \brief Discover one type of UPnP devices
	*
	* \param[in] device device type to search
	* \param[in] delay (in millisecond) maximum time for waiting any device
	*            response
	* \param[in] multicastif If not NULL, used instead of the default
	*            multicast interface for sending SSDP discover packets
	* \param[in] minissdpdsock Path to minissdpd socket, default is used if
	*            NULL
	* \param[in] localport Source port to send SSDP packets.
	*            #UPNP_LOCAL_PORT_SAME for 1900 (same as destination port)
	*            #UPNP_LOCAL_PORT_ANY to let system assign a source port
	* \param[in] ipv6 0 for IPv4, 1 of IPv6
	* \param[in] ttl should default to 2 as advised by UDA 1.1
	* \param[out] error error code when NULL is returned
	* \return NULL or a linked list
	*/
	upnpDiscoverDevice :: proc(device: cstring, delay: i32, multicastif: cstring, minissdpdsock: cstring, localport: i32, ipv6: i32, ttl: u8, error: ^i32) -> ^Dev ---

	/*!
	* \brief Discover one or several type of UPnP devices
	*
	* \param[in] deviceTypes array of device types to search (ending with NULL)
	* \param[in] delay (in millisecond) maximum time for waiting any device
	*            response
	* \param[in] multicastif If not NULL, used instead of the default
	*            multicast interface for sending SSDP discover packets
	* \param[in] minissdpdsock Path to minissdpd socket, default is used if
	*            NULL
	* \param[in] localport Source port to send SSDP packets.
	*            #UPNP_LOCAL_PORT_SAME for 1900 (same as destination port)
	*            #UPNP_LOCAL_PORT_ANY to let system assign a source port
	* \param[in] ipv6 0 for IPv4, 1 of IPv6
	* \param[in] ttl should default to 2 as advised by UDA 1.1
	* \param[out] error error code when NULL is returned
	* \param[in] searchalltypes 0 to stop with the first type returning results
	* \return NULL or a linked list
	*/
	upnpDiscoverDevices :: proc(deviceTypes: [^]cstring, delay: i32, multicastif: cstring, minissdpdsock: cstring, localport: i32, ipv6: i32, ttl: u8, error: ^i32, searchalltypes: i32) -> ^Dev ---

	/*!
	* \brief parse root XML description of a UPnP device
	*
	* fill the IGDdatas structure.
	* \param[in] buffer character buffer containing the XML description
	* \param[in] bufsize size in bytes of the buffer
	* \param[out] data IGDdatas structure to fill
	*/
	parserootdesc :: proc(buffer: cstring, bufsize: i32, data: ^Igddatas) ---
}

/*!
* \brief structure used to get fast access to urls
*/
Urls :: struct {
	/*! \brief controlURL of the WANIPConnection */
	controlURL: cstring,

	/*! \brief url of the description of the WANIPConnection */
	ipcondescURL: cstring,

	/*! \brief controlURL of the WANCommonInterfaceConfig */
	controlURL_CIF: cstring,

	/*! \brief controlURL of the WANIPv6FirewallControl */
	controlURL_6FC: cstring,

	/*! \brief url of the root description */
	rootdescURL: cstring,
}

/*! \brief NO IGD found */
NO_IGD :: (0)

/*! \brief valid and connected IGD */
CONNECTED_IGD :: (1)

/*! \brief valid and connected IGD but with a reserved address
* (non routable) */
PRIVATEIP_IGD :: (2)

/*! \brief valid but not connected IGD */
DISCONNECTED_IGD :: (3)

/*! \brief UPnP device not recognized as an IGD */
UNKNOWN_DEVICE :: (4)

@(default_calling_convention="c")
foreign lib {
	/*!
	* \brief look for a valid and possibly connected IGD in the list
	*
	* In any non zero return case, the urls and data structures
	* passed as parameters are set. Donc forget to call FreeUPNPUrls(urls) to
	* free allocated memory.
	* \param[in] devlist A device list obtained with upnpDiscover() /
	*            upnpDiscoverAll() / upnpDiscoverDevice() / upnpDiscoverDevices()
	* \param[out] urls Urls for the IGD found
	* \param[out] data datas for the IGD found
	* \param[out] lanaddr buffer to copy the local address of the host to reach the IGD
	* \param[in] lanaddrlen size of the lanaddr buffer
	* \param[out] wanaddr buffer to copy the public address of the IGD
	* \param[in] wanaddrlen size of the wanaddr buffer
	* \return #UPNP_NO_IGD / #UPNP_CONNECTED_IGD / #UPNP_PRIVATEIP_IGD /
	*         #UPNP_DISCONNECTED_IGD / #UPNP_UNKNOWN_DEVICE
	*/
	UPNP_GetValidIGD :: proc(devlist: ^Dev, urls: ^Urls, data: ^Igddatas, lanaddr: cstring, lanaddrlen: i32, wanaddr: cstring, wanaddrlen: i32) -> i32 ---

	/*!
	* \brief Get IGD URLs and data for URL
	*
	* Used when skipping the discovery process.
	* \param[in] rootdescurl Root description URL of the device
	* \param[out] urls Urls for the IGD found
	* \param[out] data datas for the IGD found
	* \param[out] lanaddr buffer to copy the local address of the host to reach the IGD
	* \param[in] lanaddrlen size of the lanaddr buffer
	* \return 0 Not ok / 1 OK
	*/
	UPNP_GetIGDFromUrl :: proc(rootdescurl: cstring, urls: ^Urls, data: ^Igddatas, lanaddr: cstring, lanaddrlen: i32) -> i32 ---

	/*!
	* \brief Prepare the URLs for usage
	*
	* build absolute URLs from the root description
	* \param[out] urls URL structure to initialize
	* \param[in] data datas for the IGD
	* \param[in] descURL root description URL for the IGD
	* \param[in] scope_id if not 0, add the scope to the linklocal IPv6
	*            addresses in URLs
	*/
	GetUPNPUrls :: proc(urls: ^Urls, data: ^Igddatas, descURL: cstring, scope_id: u32) ---

	/*!
	* \brief free the members of a UPNPUrls struct
	*
	* All URLs buffers are freed and zeroed
	* \param[out] urls URL structure to free
	*/
	FreeUPNPUrls :: proc(urls: ^Urls) ---

	/*!
	* \brief check the current connection status of an IGD
	*
	* it uses UPNP_GetStatusInfo()
	* \param[in] urls IGD URLs
	* \param[in] data IGD data
	* \return 1 Connected / 0 Disconnected
	*/
	UPNPIGD_IsConnected :: proc(urls: ^Urls, data: ^Igddatas) -> i32 ---
}

