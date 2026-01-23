/* $Id: upnpcommands.h,v 1.36 2025/03/18 23:40:15 nanard Exp $ */
/* vim: tabstop=4 shiftwidth=4 noexpandtab
 * Project: miniupnp
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * Author: Thomas Bernard
 * Copyright (c) 2005-2025 Thomas Bernard
 * This software is subject to the conditions detailed in the
 * LICENCE file provided within this distribution */
package mini_upnp

import "core:c"

when ODIN_OS == .Linux {
	foreign import lib {"libminiupnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"libminiupnpc.lib"}
}


/* MiniUPnPc return codes : */
/*! \brief value for success */
UPNPCOMMAND_SUCCESS :: (0)

/*! \brief value for unknown error */
UPNPCOMMAND_UNKNOWN_ERROR :: (-1)

/*! \brief error while checking the arguments */
UPNPCOMMAND_INVALID_ARGS :: (-2)

/*! \brief HTTP communication error */
UPNPCOMMAND_HTTP_ERROR :: (-3)

/*! \brief The response contains invalid values */
UPNPCOMMAND_INVALID_RESPONSE :: (-4)

/*! \brief Memory allocation error */
UPNPCOMMAND_MEM_ALLOC_ERROR :: (-5)

@(default_calling_convention="c")
foreign lib {
	/*! \brief WANCommonInterfaceConfig:GetTotalBytesSent
	*
	* Note: this is a 32bits unsigned value and rolls over to 0 after reaching
	* the maximum value
	*
	* \param[in] controlURL controlURL of the WANCommonInterfaceConfig of
	*            a WANDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
	*/
	UPNP_GetTotalBytesSent :: proc(controlURL: cstring, servicetype: cstring) -> u64 ---

	/*! \brief WANCommonInterfaceConfig:GetTotalBytesReceived
	*
	* Note: this is a 32bits unsigned value and rolls over to 0 after reaching
	* the maximum value
	*
	* \param[in] controlURL controlURL of the WANCommonInterfaceConfig of a WANDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
	*/
	UPNP_GetTotalBytesReceived :: proc(controlURL: cstring, servicetype: cstring) -> u64 ---

	/*! \brief WANCommonInterfaceConfig:GetTotalPacketsSent
	*
	* Note: this is a 32bits unsigned value and rolls over to 0 after reaching
	* the maximum value
	*
	* \param[in] controlURL controlURL of the WANCommonInterfaceConfig of a WANDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
	*/
	UPNP_GetTotalPacketsSent :: proc(controlURL: cstring, servicetype: cstring) -> u64 ---

	/*! \brief WANCommonInterfaceConfig:GetTotalBytesReceived
	*
	* Note: this is a 32bits unsigned value and rolls over to 0 after reaching
	* the maximum value
	*
	* \param[in] controlURL controlURL of the WANCommonInterfaceConfig of a WANDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
	*/
	UPNP_GetTotalPacketsReceived :: proc(controlURL: cstring, servicetype: cstring) -> u64 ---

	/*! \brief WANIPConnection:GetStatusInfo()
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[out] status 64 bytes buffer : `Unconfigured`, `Connecting`,
	*             `Connected`, `PendingDisconnect`, `Disconnecting`, `Disconnected`
	* \param[out] uptime time in seconds
	* \param[out] lastconnerror 64 bytes buffer : `ERROR_NONE`,
	*             `ERROR_COMMAND_ABORTED`, `ERROR_NOT_ENABLED_FOR_INTERNET`,
	*             `ERROR_USER_DISCONNECT`, `ERROR_ISP_DISCONNECT`,
	*             `ERROR_IDLE_DISCONNECT`, `ERROR_FORCED_DISCONNECT`,
	*             `ERROR_NO_CARRIER`, `ERROR_IP_CONFIGURATION`, `ERROR_UNKNOWN`
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error code
	*/
	UPNP_GetStatusInfo :: proc(controlURL: cstring, servicetype: cstring, status: cstring, uptime: ^u32, lastconnerror: cstring) -> i32 ---

	/*! \brief WANIPConnection:GetConnectionTypeInfo()
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[out] connectionType 64 characters buffer : `Unconfigured`,
	*             `IP_Routed`, `IP_Bridged`
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error code
	*/
	UPNP_GetConnectionTypeInfo :: proc(controlURL: cstring, servicetype: cstring, connectionType: cstring) -> i32 ---

	/*! \brief WANIPConnection:GetExternalIPAddress()
	*
	* possible UPnP Errors :
	* - 402 Invalid Args - See UPnP Device Architecture section on Control.
	* - 501 Action Failed - See UPnP Device Architecture section on Control.
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[out] extIpAdd 16 bytes buffer
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_UNKNOWN_ERROR,
	*         #UPNPCOMMAND_INVALID_ARGS, #UPNPCOMMAND_HTTP_ERROR or an
	*         UPnP error code
	*/
	UPNP_GetExternalIPAddress :: proc(controlURL: cstring, servicetype: cstring, extIpAdd: cstring) -> i32 ---

	/*! \brief UPNP_GetLinkLayerMaxBitRates()
	* call `WANCommonInterfaceConfig:GetCommonLinkProperties`
	*
	* \param[in] controlURL controlURL of the WANCommonInterfaceConfig of a WANDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
	* \param[out] bitrateDown bits per second
	* \param[out] bitrateUp bits per second
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error Code.
	*/
	UPNP_GetLinkLayerMaxBitRates :: proc(controlURL: cstring, servicetype: cstring, bitrateDown: ^u32, bitrateUp: ^u32) -> i32 ---

	/*! \brief WANIPConnection:AddPortMapping()
	*
	* List of possible UPnP errors for AddPortMapping :
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | -----------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 501 Action Failed | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 715 WildCardNotPermittedInSrcIP | The source IP address cannot be wild-carded
	* 716 WildCardNotPermittedInExtPort | The external port cannot be wild-carded
	* 718 ConflictInMappingEntry | The port mapping entry specified conflicts with a mapping assigned previously to another client
	* 724 SamePortValuesRequired | Internal and External port values must be the same
	* 725 OnlyPermanentLeasesSupported | The NAT implementation only supports permanent lease times on port mappings
	* 726 RemoteHostOnlySupportsWildcard | RemoteHost must be a wildcard and cannot be a specific IP address or DNS name
	* 727 ExternalPortOnlySupportsWildcard | ExternalPort must be a wildcard and cannot be a specific port value
	* 728 NoPortMapsAvailable | There are not enough free ports available to complete port mapping.
	* 729 ConflictWithOtherMechanisms | Attempted port mapping is not allowed due to conflict with other mechanisms.
	* 732 WildCardNotPermittedInIntPort | The internal port cannot be wild-carded
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[in] extPort External port
	* \param[in] inPort Internal port
	* \param[in] inClient IP of Internal client.
	* \param[in] desc Port Mapping description. if NULL, defaults to
	*            "libminiupnpc"
	* \param[in] proto `TCP` or `UDP`
	* \param[in] remoteHost IP or empty string for wildcard. Most IGD don't
	*            support it
	* \param[in] leaseDuration between 0 and 604800
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_MEM_ALLOC_ERROR, #UPNPCOMMAND_HTTP_ERROR,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP error code.
	*/
	UPNP_AddPortMapping :: proc(controlURL: cstring, servicetype: cstring, extPort: cstring, inPort: cstring, inClient: cstring, desc: cstring, proto: cstring, remoteHost: cstring, leaseDuration: cstring) -> i32 ---

	/*! \brief WANIPConnection:AddAnyPortMapping()
	*
	* Only in WANIPConnection:2
	*
	* List of possible UPnP errors for AddPortMapping :
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 501 Action Failed | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 715 WildCardNotPermittedInSrcIP | The source IP address cannot be wild-carded
	* 716 WildCardNotPermittedInExtPort | The external port cannot be wild-carded
	* 728 NoPortMapsAvailable | There are not enough free ports available to complete port mapping.
	* 729 ConflictWithOtherMechanisms | Attempted port mapping is not allowed due to conflict with other mechanisms.
	* 732 WildCardNotPermittedInIntPort | The internal port cannot be wild-carded
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:2
	* \param[in] extPort External port
	* \param[in] inPort Internal port
	* \param[in] inClient IP of Internal client.
	* \param[in] desc Port Mapping description. if NULL, defaults to
	*            "libminiupnpc"
	* \param[in] proto `TCP` or `UDP`
	* \param[in] remoteHost IP or empty string for wildcard. Most IGD don't
	*            support it
	* \param[in] leaseDuration between 0 and 604800
	* \param[out] reservedPort 6 bytes buffer
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_MEM_ALLOC_ERROR, #UPNPCOMMAND_HTTP_ERROR,
	*         #UPNPCOMMAND_INVALID_RESPONSE, #UPNPCOMMAND_UNKNOWN_ERROR
	*         or a UPnP error code.
	*/
	UPNP_AddAnyPortMapping :: proc(controlURL: cstring, servicetype: cstring, extPort: cstring, inPort: cstring, inClient: cstring, desc: cstring, proto: cstring, remoteHost: cstring, leaseDuration: cstring, reservedPort: cstring) -> i32 ---

	/*! \brief WANIPConnection:DeletePortMapping()
	*
	* Use same argument values as what was used for UPNP_AddPortMapping()
	*
	* List of possible UPnP errors for UPNP_DeletePortMapping() :
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 714 NoSuchEntryInArray | The specified value does not exist in the array
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[in] extPort External port
	* \param[in] proto `TCP` or `UDP`
	* \param[in] remoteHost IP or empty string for wildcard. Most IGD don't
	*            support it
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_MEM_ALLOC_ERROR, #UPNPCOMMAND_HTTP_ERROR,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP error code.
	*/
	UPNP_DeletePortMapping :: proc(controlURL: cstring, servicetype: cstring, extPort: cstring, proto: cstring, remoteHost: cstring) -> i32 ---

	/*! \brief WANIPConnection:DeletePortRangeMapping()
	*
	* Only in WANIPConnection:2
	* Use same argument values as what was used for AddPortMapping().
	* remoteHost is usually NULL because IGD don't support it.
	* Return Values :
	* 0 : SUCCESS
	* NON ZERO : error. Either an UPnP error code or an undefined error.
	*
	* List of possible UPnP errors for DeletePortMapping :
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 730 PortMappingNotFound | This error message is returned if no port mapping is found in the specified range.
	* 733 InconsistentParameters | NewStartPort and NewEndPort values are not consistent.
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:2
	* \param[in] extPortStart External port range start
	* \param[in] extPortEnd External port range end
	* \param[in] proto `TCP` or `UDP`
	* \param[in] manage `0` to remove only the port mappings of this IGD,
	*            `1` to remove port mappings also for other clients
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_MEM_ALLOC_ERROR, #UPNPCOMMAND_HTTP_ERROR,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP error code.
	*/
	UPNP_DeletePortMappingRange :: proc(controlURL: cstring, servicetype: cstring, extPortStart: cstring, extPortEnd: cstring, proto: cstring, manage: cstring) -> i32 ---

	/*! \brief WANIPConnection:GetPortMappingNumberOfEntries()
	*
	* not supported by all routers
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[out] numEntries Port mappings count
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_HTTP_ERROR,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP error code.
	*/
	UPNP_GetPortMappingNumberOfEntries :: proc(controlURL: cstring, servicetype: cstring, numEntries: ^u32) -> i32 ---

	/*! \brief retrieves an existing port mapping for a port:protocol
	*
	* List of possible UPnP errors for UPNP_GetSpecificPortMappingEntry() :
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 501 Action Failed | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 714 NoSuchEntryInArray | The specified value does not exist in the array.
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[in] extPort External port
	* \param[in] proto `TCP` or `UDP`
	* \param[in] remoteHost IP or empty string for wildcard. Most IGD don't
	*            support it
	* \param[out] intClient 16 bytes buffer
	* \param[out] intPort 6 bytes buffer
	* \param[out] desc 80 bytes buffer
	* \param[out] enabled 4 bytes buffer
	* \param[out] leaseDuration 16 bytes
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error Code.
	*/
	UPNP_GetSpecificPortMappingEntry :: proc(controlURL: cstring, servicetype: cstring, extPort: cstring, proto: cstring, remoteHost: cstring, intClient: cstring, intPort: cstring, desc: cstring, enabled: cstring, leaseDuration: cstring) -> i32 ---

	/*! \brief retrieves an existing port mapping for a port:protocol
	*
	* List of possible UPnP errors for UPNP_GetSpecificPortMappingEntry() :
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 501 Action Failed | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 714 NoSuchEntryInArray | The specified value does not exist in the array.
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[in] extPort External port
	* \param[in] proto `TCP` or `UDP`
	* \param[in] remoteHost IP or empty string for wildcard. Most IGD don't
	*            support it
	* \param[out] intClient 16 bytes buffer
	* \param[out] intPort 6 bytes buffer
	* \param[out] desc desclen bytes buffer
	* \param[in] desclen desc buffer length
	* \param[out] enabled 4 bytes buffer
	* \param[out] leaseDuration 16 bytes
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error Code.
	*/
	UPNP_GetSpecificPortMappingEntryExt :: proc(controlURL: cstring, servicetype: cstring, extPort: cstring, proto: cstring, remoteHost: cstring, intClient: cstring, intPort: cstring, desc: cstring, desclen: c.size_t, enabled: cstring, leaseDuration: cstring) -> i32 ---

	/*! \brief WANIPConnection:GetGenericPortMappingEntry()
	*
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 713 SpecifiedArrayIndexInvalid | The specified array index is out of bounds
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[in] index
	* \param[out] extPort 6 bytes buffer
	* \param[out] intClient 16 bytes buffer
	* \param[out] intPort 6 bytes buffer
	* \param[out] protocol 4 bytes buffer
	* \param[out] desc 80 bytes buffer
	* \param[out] enabled 4 bytes buffer
	* \param[out] rHost 64 bytes buffer
	* \param[out] duration 16 bytes buffer
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error Code.
	*/
	UPNP_GetGenericPortMappingEntry :: proc(controlURL: cstring, servicetype: cstring, index: cstring, extPort: cstring, intClient: cstring, intPort: cstring, protocol: cstring, desc: cstring, enabled: cstring, rHost: cstring, duration: cstring) -> i32 ---

	/*! \brief WANIPConnection:GetGenericPortMappingEntry()
	*
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 402 Invalid Args | See UPnP Device Architecture section on Control.
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 713 SpecifiedArrayIndexInvalid | The specified array index is out of bounds
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:1
	* \param[in] index
	* \param[out] extPort 6 bytes buffer
	* \param[out] intClient 16 bytes buffer
	* \param[out] intPort 6 bytes buffer
	* \param[out] protocol 4 bytes buffer
	* \param[out] desc desclen bytes buffer
	* \param[in] desclen desc buffer length
	* \param[out] enabled 4 bytes buffer
	* \param[out] rHost desclen bytes buffer
	* \param[in] rHostlen rHost buffer length
	* \param[out] duration 16 bytes buffer
	* \return #UPNPCOMMAND_SUCCESS, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_UNKNOWN_ERROR or a UPnP Error Code.
	*/
	UPNP_GetGenericPortMappingEntryExt :: proc(controlURL: cstring, servicetype: cstring, index: cstring, extPort: cstring, intClient: cstring, intPort: cstring, protocol: cstring, desc: cstring, desclen: c.size_t, enabled: cstring, rHost: cstring, rHostlen: c.size_t, duration: cstring) -> i32 ---

	/*! \brief  retrieval of a list of existing port mappings
	*
	* Available in IGD v2 : WANIPConnection:GetListOfPortMappings()
	*
	* errorCode errorDescription (short) | Description (long)
	* ---------------------------------- | ------------------
	* 606 Action not authorized | The action requested REQUIRES authorization and the sender was not authorized.
	* 730 PortMappingNotFound | no port mapping is found in the specified range.
	* 733 InconsistantParameters | NewStartPort and NewEndPort values are not consistent.
	*
	* \param[in] controlURL controlURL of the WANIPConnection of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPConnection:2
	* \param[in] startPort port interval start
	* \param[in] endPort port interval end
	* \param[in] protocol `TCP` or `UDP`
	* \param[in] numberOfPorts size limit of the list returned. `0` to request
	*            all port mappings
	* \param[out] data port mappings list
	*/
	UPNP_GetListOfPortMappings :: proc(controlURL: cstring, servicetype: cstring, startPort: cstring, endPort: cstring, protocol: cstring, numberOfPorts: cstring, data: ^Port_Mapping_Parser_Data) -> i32 ---

	/*! \brief GetFirewallStatus() retrieves whether the firewall is enabled
	* and pinhole can be created through UPnP
	*
	* IGD:2, functions for service WANIPv6FirewallControl:1
	*
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[out] firewallEnabled false (0) or true (1)
	* \param[out] inboundPinholeAllowed false (0) or true (1)
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_GetFirewallStatus :: proc(controlURL: cstring, servicetype: cstring, firewallEnabled: ^i32, inboundPinholeAllowed: ^i32) -> i32 ---

	/*! \brief retrieve default value after which automatically created pinholes
	* expire
	*
	* The returned value may be specific to the \p proto, \p remoteHost,
	* \p remotePort, \p intClient and \p intPort, but this behavior depends
	* on the implementation of the firewall.
	*
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[in] remoteHost
	* \param[in] remotePort
	* \param[in] intClient
	* \param[in] intPort
	* \param[in] proto `TCP` or `UDP`
	* \param[out] opTimeout lifetime in seconds of an inbound "automatic"
	*             firewall pinhole created by an outbound traffic initiation.
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_GetOutboundPinholeTimeout :: proc(controlURL: cstring, servicetype: cstring, remoteHost: cstring, remotePort: cstring, intClient: cstring, intPort: cstring, proto: cstring, opTimeout: ^i32) -> i32 ---

	/*! \brief create a new pinhole that allows incoming traffic to pass
	* through the firewall
	*
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[in] remoteHost literal presentation of IPv6 address or domain name.
	*            empty string for wildcard
	* \param[in] remotePort remote host port. Likely 0 (for wildcard)
	* \param[in] intClient IP address of internal client. cannot be wildcarded
	* \param[in] intPort client port. 0 for wildcard
	* \param[in] proto IP protocol integer (6 for TCP, 17 for UDP, etc.)
	*            65535 for wildcard.
	* \param[in] leaseTime in seconds
	* \param[out] uniqueID 8 bytes buffer
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_AddPinhole :: proc(controlURL: cstring, servicetype: cstring, remoteHost: cstring, remotePort: cstring, intClient: cstring, intPort: cstring, proto: cstring, leaseTime: cstring, uniqueID: cstring) -> i32 ---

	/*! \brief update a pinhole’s lease time
	*
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[in] uniqueID value obtained through UPNP_AddPinhole()
	* \param[in] leaseTime in seconds
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_UpdatePinhole :: proc(controlURL: cstring, servicetype: cstring, uniqueID: cstring, leaseTime: cstring) -> i32 ---

	/*! \brief remove a pinhole
	*
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[in] uniqueID value obtained through UPNP_AddPinhole()
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_DeletePinhole :: proc(controlURL: cstring, servicetype: cstring, uniqueID: cstring) -> i32 ---

	/*! \brief checking if a certain pinhole allows traffic to pass through the firewall
	*
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[in] uniqueID value obtained through UPNP_AddPinhole()
	* \param[out] isWorking `0` for false, `1` for true
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_CheckPinholeWorking :: proc(controlURL: cstring, servicetype: cstring, uniqueID: cstring, isWorking: ^i32) -> i32 ---

	/*! \brief get the total number of IP packets which have been going through
	* the specified pinhole
	* \todo \p packets should be #UNSIGNED_INTEGER
	* \param[in] controlURL controlURL of the WANIPv6FirewallControl of a
	*            WANConnectionDevice
	* \param[in] servicetype urn:schemas-upnp-org:service:WANIPv6FirewallControl:1
	* \param[in] uniqueID value obtained through UPNP_AddPinhole()
	* \param[out] packets how many IP packets have been going through the
	*             specified pinhole
	* \return #UPNPCOMMAND_UNKNOWN_ERROR, #UPNPCOMMAND_INVALID_ARGS,
	*         #UPNPCOMMAND_HTTP_ERROR, #UPNPCOMMAND_SUCCESS or an UPnP error code
	*/
	UPNP_GetPinholePackets :: proc(controlURL: cstring, servicetype: cstring, uniqueID: cstring, packets: ^i32) -> i32 ---
}

