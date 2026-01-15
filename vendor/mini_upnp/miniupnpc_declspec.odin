package mini_upnp

when ODIN_OS == .Linux {
	foreign import lib {"upnpc.a"}
} else when ODIN_OS == .Windows {
	foreign import lib {"upnpc.lib"}
}


