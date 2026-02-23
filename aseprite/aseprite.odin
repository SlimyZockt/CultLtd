package aseprite

import "base:runtime"
import "core:log"
import os "core:os"
import fp "core:path/filepath"
import "core:strings"

ASEPRITE_PATH :: "aseprite"
ASSETS_PATH :: "./assets/"


main :: proc() {
	context.logger = log.create_console_logger()
	genereate_png_from_ase(ASEPRITE_PATH, ASSETS_PATH, context.allocator)
}

genereate_png_from_ase :: proc(aseprite_path, assets_path: string, allocator: runtime.Allocator) {
	context.allocator = allocator
	w := os.walker_create(assets_path)

	for fi in os.walker_walk(&w) {
		ext := fp.ext(fi.name)
		if !(ext == ".aseprite" || ext == ".ase") do continue

		log.info(fi.name)


		pd: os.Process_Desc
		target_path := strings.join(
			{pd.working_dir, "/", fp.short_stem(fi.name), ".png"},
			"",
			allocator,
		)
		defer delete(target_path)

		pd.working_dir = fp.dir(fi.fullpath)
		pd.command = {aseprite_path, "-b", fi.fullpath, "--sheet", target_path}

		_, stdout, stderr, err := os.process_exec(pd, allocator)
		assert(err == nil)
		log.debug(stdout, stderr)
		delete(stdout)
		delete(stderr)
	}
}
