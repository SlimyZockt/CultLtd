package aseprite

import "core:bytes"
import "core:fmt"

ase_file: []u8 = #load("../assets/sprites/char.aseprite")

HeaderFlagsBits :: enum u8 {
	LayerOpacity,
	LayerGroups,
	LayerUUID,
}

HeaderFlags :: bit_set[HeaderFlagsBits;u32]

Header :: struct #packed {
	file_size:         u32,
	magic_number:      u16,
	frames:            u16,
	width:             u16,
	height:            u16,
	color_depth:       u16,
	flags:             HeaderFlags,
	_speed:            u16,
	_:                 [2]u32,
	transparent_index: u8,
	_:                 [3]u8,
	color_count:       u16,
	pixel_width:       u8,
	pixel_height:      u8,
	grid_x:            i16,
	grid_y:            i16,
	grid_width:        u16,
	grid_height:       u16,
	_:                 [84]u8,
}
#assert(size_of(Header) == 128)

Frame :: struct #packed {
	bytes:        u32,
	magic_number: u16,
	_chunk_count: u16,
	duration:     u16,
	_:            [2]u8,
	chunk_count:  u32,
}
#assert(size_of(Frame) == 16)

FrameChunk :: struct {
	type: u16,
	size: u32,
	data: union {
		OldPaletteChunk,
		LayerChunk,
	},
}

OldPaletteChunk :: struct {
	packes_count: i16,
	packes:       [dynamic]struct {
		enries:      u8,
		color_count: u8,
		color:       [dynamic][3]u8,
	},
}

LayerFlagsBits :: enum u16 {
	Visible,
	Editable,
	LockMovement,
	Background,
	PreferLinkedCels,
	LayerGroupCollapsed,
	ReferenceLayer,
}

LayerFlags :: bit_set[LayerFlagsBits;u16]

LayerType :: enum u16 {
	Normal  = 0,
	Group   = 1,
	TileMap = 2,
}

LayerBlend :: enum u16 {
	Normal     = 0,
	Multiply   = 1,
	Screen     = 2,
	Overlay    = 3,
	Darken     = 4,
	Lighten    = 5,
	ColorDodge = 6,
	ColorBurn  = 7,
	HardLight  = 8,
	SoftLight  = 9,
	Difference = 10,
	Exclusion  = 11,
	Hue        = 12,
	Saturation = 13,
	Color      = 14,
	Luminosity = 15,
	Addition   = 16,
	Subtract   = 17,
	Divide     = 18,
}


LayerChunk :: #packed struct {
	flags:       LayerFlags,
	type:        LayerType,
	child_level: u16,
	_width:      u16,
	_height:     u16,
	blend_mode:     LayerBlend,
}


main :: proc() {
	temp := transmute(^AsepriteHeader)(&ase_file[0])
	fmt.printfln("AseHeader: %v", temp)
	fmt.printfln("%v", size_of(AsepriteHeader))
	fmt.printfln("%v", size_of(AsepriteFrame))
	fmt.printfln("%v", size_of(AsepriteFrameChunk))
}
