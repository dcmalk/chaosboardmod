# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Chaos Mod is a comprehensive Trailmakers game mod that provides 16+ entertaining effects for multiplayer chaos and fun. Originally evolved from MegadrillSeat, it now features a complete chaos interface with destructive effects, creature spawns, physics manipulation, and environmental control.

## Architecture

- **main.lua**: Complete chaos mod implementation (~500 lines) using the Trailmakers modding API (tm.*). Features modular effect functions, universal cooldown system, error handling with pcall, and organized UI categories.
- **info.json**: Updated mod metadata reflecting the new Chaos Mod functionality and feature set.
- **docs/**: Reference documentation for the Trailmakers modding API, including:
  - **trailmakers_docs.lua**: Complete API type definitions with detailed documentation
  - **trailmakers_spawnables.txt**: List of all spawnable prefab names (used extensively for effects)
  - **trailmakers_audio.txt**: List of all available audio event names (used for authentic sound effects)
  - Sample mod files for reference

## Key Components

### Enhanced Megadrill Pulse System
- **True Force Push**: Distance-based force calculation affecting all players within 50-unit radius
- **Player Elimination**: Kills players not in vehicles (authentic boss battle behavior)
- **Directional Physics**: Pushes players away from triggerer with upward component
- **Visual/Audio**: Uses authentic Megadrill explosion and sound effects

### Effect Categories
1. **Destruction Effects** (5 effects):
   - Megadrill Pulse: Force push + player elimination
   - Barrel Rain: 50 falling barrels (30% explosive)
   - Fireworks Show: 25 varied explosions with authentic sounds
   - Mine Field: 30 landmines scattered around area
   - Gravity Bomb: Extreme gravity for dramatic falls

2. **Creature Spawns** (3 effects):
   - Whale Rain: 5 whales dropped from sky with whale sounds
   - Animal Swarm: 20 mixed hostile creatures (chasers, runners, nugget thieves)
   - Sheep Invasion: 15 peaceful sheep for comedic effect

3. **Physics Chaos** (5 effects):
   - Slow Motion: 0.2x time scale
   - Speed Up: 2.0x time scale
   - Low Gravity: 3 gravity units (vs normal 14)
   - Reverse Gravity: -8 gravity (everything falls up!)
   - Structure Launcher: Massive upward force on all vehicles

4. **Environmental/Control** (3 effects):
   - Teleport Party: Attempts to bring all players to triggerer
   - Cleanup All: Removes all spawned objects
   - Reset Physics: Restores normal gravity and time

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

Check `D:\Program Files (x86)\Steam\steamapps\common\Trailmakers\mods\MegadrillSeat.log` for runtime errors. The mod includes:
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
- Dynamic data goes in `data_dynamic_willNotBeUploadedToWorkshop/` (read/write, local only)
- Documentation and examples in `docs/` folder provide comprehensive API reference