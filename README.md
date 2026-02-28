# HoverCasts

**HoverCasts** is a lightweight World of Warcraft Retail addon that displays your Blizzard click-cast bindings directly at the mouse cursor when hovering supported unit frames.

Designed for healers and support players who want instant visibility into their click-cast setup—without opening menus or remembering modifier combinations.

## Download

Download HoverCasts on CurseForge:  
https://www.curseforge.com/wow/addons/hovercasts

## Features

- Displays Blizzard Click Casting bindings on hover
- Modifier-aware (Shift / Ctrl / Alt)
- Clean, compact tooltip near the cursor
- Smart positioning (never off-screen)
- Displays:
  - Mouse button
  - Spell or action name
  - Mana cost
  - Remaining cooldown
- Active cooldown dimming
- Retail-safe cooldown handling (no taint errors)
- Frame-type toggles (enable/disable specific unit frames)
- Lightweight and minimal
- No configuration UI

## Supported Frames

Enabled by default:

- Party frames
- Raid frames
- Focus frame

Optional (toggle via command):

- Player frame
- Target frame
- Enemy-related units (target-of-target, focus target, etc.)
- World units (mouseover NPCs)

## Commands

/hc  
Show help.

/hc refresh  
Refresh click-cast bindings.

/hc strict  
Only show when hovering supported Blizzard unit frames.

/hc frames  
Display current frame toggle status.

/hc frame <type>  
Toggle a frame type.

/hc frame <type> on  
Enable a frame type.

/hc frame <type> off  
Disable a frame type.

Valid frame types:

party  
raid  
focus  
player  
target  
enemy  
world  

Example:

/hc frame player on

## Requirements

- World of Warcraft Retail
- Blizzard Click Casting enabled (Game Menu → Keybindings → Click Casting)

## Philosophy

HoverCasts intentionally does **one thing well**:
show you what will happen *before* you click.

No configuration UI.  
No profiles.  
No reinvention of click-casting—just visibility.

## License

MIT (or update if you prefer a different license).