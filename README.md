# Chaosboard

A Trailmakers mod providing 16+ chaos effects for multiplayer entertainment.

## Features

- **Destruction**: Barrel rain, fireworks shows, mine fields, gravity bombs
- **Creatures**: Whale summoning, animal swarms, sheep invasions  
- **Physics**: Time/gravity manipulation, vehicle launching
- **Environment**: Teleportation, energy shields, cleanup tools

## Installation

1. Clone this repository to your Trailmakers mods directory:
   ```
   git clone https://github.com/dcmalk/chaosboardmod.git
   ```
   Or download and extract to: `<Trailmakers>/mods/chaosboardmod/`

2. Ensure the folder structure is:
   ```
   Trailmakers/mods/chaosboardmod/
   ├── main.lua
   ├── info.json
   └── ...
   ```

3. Launch Trailmakers - the mod loads automatically on game start
4. In-game, the Chaosboard UI appears with buttons for all effects

## Development

This is something of a "vibe coding" experiment - a Lua mod that grew organically from testing the Trailmakers API. No build system needed, just edit `main.lua` and reload in-game.

See `CLAUDE.md` for detailed development notes and API reference materials in `docs/`.