package main

import "core:fmt"
import "core:math"
import "core:time"

@(rodata)
// sizes := [?]u32{100, 1000, 10_000}
sizes := [?]u64{100, 1000, 10_000}
TRIES :: 100

main :: proc() {
	for size in sizes {
		array_flat_time := math.F64_MAX
		array_2d_time := math.F64_MAX
		fmt.println("----------------------------------")
		fmt.printfln("Testing %v times a array of size %v", TRIES, size)
		for _ in 0 ..< TRIES {
			array_flat_time = min(flat_array_2d_bench(size), array_flat_time)
			array_2d_time = min(array_2d_bench(size), array_2d_time)

		}
		fmt.printfln("Flat array best time: %vμs", array_flat_time)
		fmt.printfln("2D array best time  : %vμs", array_2d_time)
		fmt.printfln("Flat is %.2f times faster", array_2d_time / array_flat_time)
	}
}

array_2d_bench :: proc(size: u64) -> f64 {
	array_2d := make([][]u64, size)
	for &e in array_2d {
		e = make([]u64, size)
	}

	defer {
		for e in array_2d {
			delete(e)
		}
		delete(array_2d)
	}


	start := time.now()
	for y in 0 ..< size {
		for x in 0 ..< size {
			array_2d[x][y] = x + y
		}
	}
	end := time.now()


	return time.duration_microseconds(time.diff(start, end))
}

flat_array_2d_bench :: proc(size: u64) -> f64 {
	array_flat_2d := make([]u64, size * size)
	defer delete(array_flat_2d)

	start := time.now()
	for y in 0 ..< size {
		for x in 0 ..< size {
			array_flat_2d[x + y * size] = x + y
		}
	}
	end := time.now()

	return time.duration_microseconds(time.diff(start, end))
}
