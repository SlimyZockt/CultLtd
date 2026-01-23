/* $Id: igd_desc_parse.h,v 1.14 2025/02/08 23:15:16 nanard Exp $ */
/* Project : miniupnp
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * Author : Thomas Bernard
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


/*! \file igd_desc_parse.h
* \brief API to parse UPNP device description XML
* \todo should not be exposed in the public API
*/

/*! \brief maximum lenght of URLs */
MINIUPNPC_URL_MAXSIZE :: (128)

/*! \brief Structure to store the result of the parsing of UPnP
* descriptions of Internet Gateway Devices services */
Igddatas_Service :: struct {
	/*! \brief controlURL for the service */
	controlurl: [128]i8,

	/*! \brief eventSubURL for the service */
	eventsuburl: [128]i8,

	/*! \brief SCPDURL for the service */
	scpdurl: [128]i8,

	/*! \brief serviceType */
	servicetype: [128]i8,
}

/*! \brief Structure to store the result of the parsing of UPnP
* descriptions of Internet Gateway Devices */
Igddatas :: struct {
	/*! \brief current element name */
	cureltname: [128]i8,

	/*! \brief URLBase */
	urlbase: [128]i8,

	/*! \brief presentationURL */
	presentationurl: [128]i8,

	/*! \brief depth into the XML tree */
	level: i32,

	/*! \brief "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1" */
	CIF: Igddatas_Service,

	/*! \brief first of "urn:schemas-upnp-org:service:WANIPConnection:1"
	* or "urn:schemas-upnp-org:service:WANPPPConnection:1" */
	first: Igddatas_Service,

	/*! \brief second of "urn:schemas-upnp-org:service:WANIPConnection:1"
	* or "urn:schemas-upnp-org:service:WANPPPConnection:1" */
	second: Igddatas_Service,

	/*! \brief "urn:schemas-upnp-org:service:WANIPv6FirewallControl:1" */
	IPv6FC: Igddatas_Service,

	/*! \brief currently parsed service */
	tmp: Igddatas_Service,
}

@(default_calling_convention="c")
foreign lib {
	/*!
	* \brief XML start element handler
	*/
	IGDstartelt :: proc(rawptr, cstring, i32) ---

	/*!
	* \brief XML end element handler
	*/
	IGDendelt :: proc(rawptr, cstring, i32) ---

	/*!
	* \brief XML characted data handler
	*/
	IGDdata :: proc(rawptr, cstring, i32) ---
}

