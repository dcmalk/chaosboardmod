# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CRITICAL UI LIMITATION ⚠️

**STATUS MESSAGE LENGTH LIMIT: 64 CHARACTERS MAX**

The Trailmakers modding API has a strict 64-character limit for status messages passed to `tm.playerUI.SetUIValue(playerId, "status", text)`. Exceeding this limit causes immediate game crashes.

### Rules:
- **ALWAYS count characters** before using setStatus()
- **Keep messages under 64 chars** including emojis, spaces, and variable content
- **Account for dynamic content** like numbers that could grow
- **Use abbreviations** and short phrases
- **Test edge cases** (e.g., what if a number gets very large?)

### Safe Examples:
- ✅ `"🚀 LAUNCHER! " .. count .. " vehicles launched!"` (varies ~35-45 chars)
- ✅ `"💥 EXPLOSION! " .. num .. " bursts!"` (~25-35 chars)
- ❌ `"🎆 FIREWORKS SHOW! " .. explosions .. " sky bursts lighting up the night!"` (78+ chars)
- ❌ `"🏰 BARREL FORTRESS! " .. barrels .. " barrels form protective walls around you!"` (80+ chars)

### Violation History:
This limit has caused 5+ crashes during development. It is the #1 cause of runtime failures.

## Project Overview

Chaosboard is a comprehensive Trailmakers game mod that provides 38+ entertaining effects for multiplayer chaos and fun. Originally evolved from MegadrillSeat, it now features a 3-page chaos interface with destructive effects, creature spawns, physics manipulation, environmental control, shields, shockwaves, and Frozen Tracks DLC content.

## Architecture

- **main.lua**: Complete chaos mod implementation (~2400 lines) using the Trailmakers modding API (tm.*). Features modular effect functions, universal cooldown system, error handling with pcall, and a 3-page organized UI.
- **info.json**: Updated mod metadata reflecting the new Chaosboard functionality and feature set.
- **docs/**: Reference documentation for the Trailmakers modding API, including:
  - **trailmakers_docs.lua**: Complete API type definitions with detailed documentation
  - **trailmakers_spawnables.txt**: List of all spawnable prefab names (used extensively for effects)
  - **trailmakers_audio.txt**: List of all available audio event names (used for authentic sound effects)
  - **examples/**: Sample mod implementations organized by type:
    - **blockmod/**: Basic block spawning example
    - **documentationmod/**: API documentation demonstration
    - **kickmod/**: Player management example  
    - **spawnmod/**: Simple object spawning
    - **spawnmodadv/**: Advanced spawning with custom assets (models, textures)
    - **trackmakermod/**: Track/level creation example

## Key Components

### ShockwaveManager
Inlined, frame-rate-independent animated shockwave system. Spawns rings of explosions outward from a point over time using a configurable scale sequence and interval. Handles auto-cleanup of completed shockwaves after a delay.

### Effect Categories (3-page UI)

**Page 1 — Core Chaos:**
1. **Destruction** (7 effects): Barrel Rain, Barrel Fortress, PowerCore House, Fireworks Show, Mine Field, Gravity Bomb, Launch All Vehicles
2. **Creatures** (6 effects): Whale Rain, Animal Swarm, Sheep Invasion, Chirpo Army, Timeline Pod Landing, Chirpo Spaceship
3. **Physics** (5 effects): Slow Motion (0.2x), Speed Up (2.0x), Low Gravity (3 units vs normal 14), Reverse Gravity (-8 units), Reset Physics

**Page 2 — Advanced Effects:**
4. **Shields** (10 effects): Ground Shield (Megadrill Pulse), Small/Medium/Large Sky Shields, Ring Light Show, Energy Trail, Crystal Garden, Top Half-Sphere, Shield Trap, Mega Shield Trap
5. **Chaos Effects** (13 effects): Poison Rain, Snowball Fight, Crystal Cavern, Ring of Fire, Bone Graveyard, Boulder Avalanche, Total Chaos, Chaos Trap, Ring Shockwave, True Shockwave, Fire Inferno, Carpet Bombing, Flame Mandala
6. **Controls** (4 effects): Cleanup All, Cleanup Shields, Teleport Party, Emergency Teleport

**Page 3 — Frozen Tracks DLC:**
7. **DLC Content** (6 effects): Buildings, LED Signs, Race Track, Environment, Infrastructure, Special Objects

### Core Systems
- **Universal Cooldown**: 2-second cooldown across all abilities prevents spam
- **Error Handling**: All effects wrapped in pcall with error logging and user feedback
- **Safe Operations**: Fallback systems for missing prefabs/audio, null checks for API calls
- **Status Feedback**: Real-time updates showing effect results and cooldown status

### Player Management
- Event-driven player join handling creates full UI for each player
- Per-player cooldown tracking and status display
- Structured UI with category labels and organized button layout
- Emoji-enhanced button labels for visual appeal

### API Usage
- **Comprehensive tm.* API usage**:
  - `tm.players.*` for player management, structure access, teleportation, and elimination
  - `tm.playerUI.*` for complex UI creation with labels and buttons
  - `tm.physics.*` for object spawning, gravity/time manipulation, and cleanup
  - `tm.audio.*` for authentic game sound effects
  - `tm.vector3.*` for 3D position calculations and force vectors
  - `tm.os.*` for timing and logging

## Development Notes

- **Modular Design**: Each effect is a separate function for easy maintenance and testing
- **Defensive Programming**: Extensive error handling, null checks, and fallback mechanisms
- **Performance Conscious**: Reasonable spawn limits (MAX_SPAWNS_PER_ABILITY = 50)
- **Authentic Experience**: Uses official game audio and visual effects where possible
- **Player Safety**: Respects CanKillPlayer() and other safety checks
- **Multiplayer Focused**: Effects designed for entertaining group interactions

## Testing and Debugging

Check `D:\Program Files (x86)\Steam\steamapps\common\Trailmakers\mods\chaosboardmod.log` for runtime errors. The mod includes:
- Comprehensive error logging with ability names
- Status updates showing success/failure of operations
- No log file means successful loading without errors

## No Build System

This is a Lua-based mod with no build, test, or lint commands. Development involves:

1. Edit main.lua directly (mod auto-reloads in-game)
2. Check log file for any runtime errors
3. Use tm.os.Log() for debugging output
4. Test effects in multiplayer for best experience
5. Refer to docs/ folder for API reference and available prefabs/audio

## Configuration

Key constants at top of main.lua:
- `COOLDOWN_SEC = 2.0`: Universal cooldown between abilities
- `PULSE_RADIUS = 50.0`: Range of Megadrill pulse effect  
- `PULSE_FORCE = 200000`: Force strength for physics effects
- `MAX_SPAWNS_PER_ABILITY = 50`: Limit to prevent performance issues

## File Structure

- Static data goes in `data_static/` (read-only, uploaded to Steam Workshop)
- Dynamic data goes in `data_dynamic/` (read/write, persists between sessions — used by `tm.os.WriteAllText_Dynamic`)
- Local dev scratch files go in `local/` (gitignored, not uploaded to Workshop): spawnable reference dumps, etc.
- Documentation and examples in `docs/` folder provide comprehensive API reference