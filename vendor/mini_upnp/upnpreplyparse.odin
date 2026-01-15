/* $Id: upnpreplyparse.h,v 1.22 2025/03/29 17:58:12 nanard Exp $ */
/* MiniUPnP project
 * http://miniupnp.free.fr/ or https://miniupnp.tuxfamily.org/
 * (c) 2006-2025 Thomas Bernard
 * This software is subject to the conditions detailed
 * in the LICENCE file provided within the distribution */
package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"upnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"upnpc.lib"}
}


/*! \brief Name/Value linked list
* not exposed in the public API
*/
Name_Value :: struct {}

/*! \brief data structure for parsing */
Name_Value_Parser_Data :: struct {
	/*! \brief name/value linked list */
	l_head: ^Name_Value,

	/*! \brief current element name */
	curelt: [64]i8,

	/*! \brief port listing array */
	portListing: cstring,

	/*! \brief port listing array length */
	portListingLength: i32,

	/*! \brief flag indicating the current element is  */
	topelt: i32,

	/*! \brief top element character data */
	cdata: cstring,

	/*! \brief top element character data length */
	cdatalen: i32,
}

@(default_calling_convention="c", link_prefix="upnp")
foreign lib {
	/*!
	* \brief Parse XML and fill the structure
	*
	* \param[in] buffer XML data
	* \param[in] bufsize buffer length
	* \param[out] data structure to fill
	*/
	ParseNameValue :: proc(buffer: cstring, bufsize: i32, data: ^Name_Value_Parser_Data) ---

	/*!
	* \brief free memory
	*
	* \param[in,out] pdata data structure
	*/
	ClearNameValueList :: proc(pdata: ^Name_Value_Parser_Data) ---

	/*!
	* \brief get a value from the parsed data
	*
	* \param[in] pdata data structure
	* \param[in] name name
	* \return the value or NULL if not found
	*/
	GetValueFromNameValueList :: proc(pdata: ^Name_Value_Parser_Data, name: cstring) -> cstring ---
}

