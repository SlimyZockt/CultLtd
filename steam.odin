package main

import steam "./steamworks/"
import "core:c"
import "core:log"


steam_debug_text_hook :: proc "c" (severity: c.int, debugText: cstring) {
	// if you're running in the debugger, only warnings (nSeverity >= 1) will be sent
	// if you add -debug_steamworksapi to the command-line, a lot of extra informational messages will also be sent
	context = g_ctx
	log.info(string(debugText))

	if severity >= 1 {
		// runtime.debug_trap()
		panic("steam err")
	}
}


steam_init :: proc() {
	if steam.RestartAppIfNecessary(steam.uAppIdInvalid) {
		log.info("start through steam")
		return
	}

	err_msg: steam.SteamErrMsg
	if err := steam.InitFlat(&err_msg); err != .OK {
		log.panicf(
			`steam.InitFlat failed with code '%v' and message "%v"
            Steam Init failed. Make sure Steam is running.`,
			err,
			transmute(cstring)&err_msg[0],
		)
	}

	steam.Client_SetWarningMessageHook(steam.Client(), steam_debug_text_hook)
	steam.ManualDispatch_Init()

	// friends_handel := steam.Friends()
	// for i in 0 ..< steam.Friends_GetFriendCount(
	// 	friends_handel,
	// 	i32(steam.EFriendFlags.Immediate),
	// ) {
	// 	id := steam.Friends_GetFriendByIndex(
	// 		friends_handel,
	// 		i32(i),
	// 		i32(steam.EFriendFlags.Immediate),
	// 	)
	// 	name := steam.Friends_GetFriendPersonaName(friends_handel, id)
	// 	log.info(name)
	// }
}

steam_destroy :: proc() {
	steam.Shutdown()
}
