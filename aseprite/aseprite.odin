package aseprite

import "core:log"
import os "core:os/os2"
import fp "core:path/filepath"
import "core:strings"

ASEPRITE_PATH :: "aseprite"
ASSETS_PATH :: "./assets/"


main :: proc() {
	context.logger = log.create_console_logger()
	genereate_png_from_ase(ASEPRITE_PATH, ASSETS_PATH)
}

genereate_png_from_ase :: proc(aseprite_path, assets_path: string) {
	w := os.walker_create(assets_path)

	for fi in os.walker_walk(&w) {
		ext := fp.ext(fi.name)
		if !(ext == ".aseprite" || ext == ".ase") do continue

		log.info(fi.name)


		pd: os.Process_Desc
		pd.working_dir = fp.dir(fi.fullpath)
		pd.command = {
			aseprite_path,
			"-b",
			fi.fullpath,
			"--sheet",
			strings.join({pd.working_dir, "/", fp.short_stem(fi.name), ".png"}, ""),
		}

		state, stdout, stdin, err := os.process_exec(pd, context.allocator)
		delete(stdout)
		delete(stdin)
	}

}
