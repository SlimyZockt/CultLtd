# AGENTS.md - CultLtd. Codebase Guide

This document provides guidelines for AI coding agents working in this repository.

## Project Overview

CultLtd. is a multiplayer game written in **Odin** using:
- **Raylib** - Graphics, input, and window management
- **Steamworks SDK v1.60** - P2P networking, lobbies, matchmaking
- **Spall** - Profiling/tracing

The game features an entity-component system, 2D rendering with camera support,
fixed timestep game loop (60 Hz logic, 30 Hz network), and Steam-based multiplayer.

## Project Structure

```
/                       Main application (cultLtd.odin) - entry point, entities, rendering
/steam/                 Steam networking wrapper - lobbies, P2P connections, callbacks
/aseprite/              Asset pipeline - converts .aseprite/.ase files to PNG sprite sheets
/base/                  Base utilities
/vendor/steamworks/     Steamworks SDK bindings (Windows/Linux/macOS)
/assets/sprites/        Sprite assets (.aseprite source and generated .png)
/assets/3d/             3D assets (Blender .blend, .obj, .mtl files)
```

## Build Commands

```bash
# Standard debug build with Steam integration
odin run . --debug -define:STEAM=true

# Or use the build script
./build.sh

# Debug build without Steam
odin run . --debug -define:STEAM=false

# Release build
odin run . -o:speed -define:STEAM=true

# Headless mode (for server testing)
odin run . --debug -define:HEADLESS=true
```

**Configuration Flags**: `STEAM` (default: true), `HEADLESS` (default: false), `CULT_DEBUG` (default: ODIN_DEBUG)

**Output Binary**: `CultLtd.` in project root.

## Testing

Odin has no built-in test framework. Manual testing by running the game.
Steam networking requires: Steam client running + valid `steam_appid.txt`.

## Code Style Guidelines

### Imports
Order: base runtime, core libraries, vendor libraries, then local packages with aliases.
```odin
import "base:runtime"
import "core:fmt"
import vmem "core:mem/virtual"
import rl "vendor:raylib"
import steam "./steam/"
```

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Types/Structs | PascalCase | `EntityHandle`, `CultCtx` |
| Procedures | snake_case | `entity_add`, `update_logic` |
| Constants | SCREAMING_CASE | `LOGIC_FPS`, `MAX_PLAYER_COUNT` |
| Enum types/values | PascalCase | `Actions`, `.MainMenu` |
| Global variables | g_ prefix | `g_ctx`, `g_arena` |
| Bit sets | Bits/Flags suffix | `EntityFlagBits`, `EntityFlags` |

### Formatting
- **Indentation**: Tabs (not spaces)
- **Braces**: Same line for control structures
- **Trailing commas**: Use in multi-line struct literals

### Type Definitions
```odin
TextureId :: distinct u64              // Use distinct for type-safe IDs

EntityFlagBits :: enum u32 { Controlabe, Camera, Sync, Alive }
EntityFlags :: bit_set[EntityFlagBits;u32]  // bit_set with backing type
```

### Error Handling
```odin
assert(condition)                      // Invariants
assert(condition, "message")
ensure(err == nil, "critical error")   // Panics with message
log.error("non-fatal error")           // Logging
log.panicf("fatal: %v", err)           // Unrecoverable
```

### Comments and TODOs
```odin
// TODO(Abdul): Implement feature X
// HACK(abdul): Temporary workaround
```

### Common Attributes
```odin
@(private)                 // Package-private
@(thread_local)            // Thread-local storage
@(instrumentation_enter)   // Profiling hooks
```

### Memory Management
```odin
arena: vmem.Arena
err := vmem.arena_init_growing(&arena)
context.allocator = vmem.arena_allocator(&arena)
defer vmem.arena_destroy(&arena)

// Temporary allocations
temp := vmem.arena_temp_begin(&g_arena)
defer vmem.arena_temp_end(temp)
```

### Conditional Compilation
```odin
when STEAM { steam.init(&ctx.steam) }
when ODIN_DEBUG { /* debug-only code */ }
```

### Switch Statements
```odin
#partial switch callback.iCallback {   // Use #partial when not handling all cases
case .LobbyCreated: // handle
}
```

### C Interop
```odin
callback :: proc "c" (param: cstring) {
    context = g_ctx  // Restore Odin context first
    // ... rest of code
}
```

## Common Patterns

### Entity System
```odin
handle := entity_add(&ctx.entities, PLAYER_ENTITY)  // Add
entity := entity_get(&ctx.entities, handle)          // Get (nil if invalid)
entity_delete(&ctx.entities, handle)                 // Delete
```

### Steam Integration
```odin
steam.init(&ctx.steam)                    // Initialize
steam.create_lobby(&ctx.steam, max_size)  // Create lobby
steam.write(&ctx.steam, &data, size)      // Send data
steam.deinit(&ctx.steam)                  // Cleanup
```

## Key Files

| File | Purpose |
|------|---------|
| `cultLtd.odin` | Main entry point, game loop, rendering |
| `steam/steam.odin` | Steam networking, lobby management |
| `aseprite/aseprite.odin` | Sprite sheet generation tool |
| `build.sh` | Build script |
| `.project.gf` | Debugger configuration |
