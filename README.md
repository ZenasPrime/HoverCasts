# HoverCasts

**HoverCasts** is a lightweight World of Warcraft addon that displays your Blizzard click-cast bindings directly at the mouse cursor when hovering party, raid, or focus frames.

Designed for healers and support players who want instant visibility into their click-cast setup—without opening menus or remembering modifier combinations.

## Features

- Shows Blizzard click-cast bindings on hover
- Modifier-aware (Shift / Ctrl / Alt)
- Clean, compact tooltip near the cursor
- Displays:
  - Mouse button
  - Spell or action name
  - Mana cost
  - Cooldown (with visual dimming)
- Smart positioning (never off-screen)
- Works with default Blizzard Party, Raid, and Focus frames
- No UI clutter, no background processing

## Commands

/hc
Show help.

/hc on
Debug mode (show even without a valid unit).

/hc off
Hide the tooltip.

/hc referesh
Refresh click-cast bindings.

/hc strict
Only show when hovering supported Blizzard unit frames.

## Requirements

- World of Warcraft Retail
- Blizzard Click Casting enabled (Interface → Keybindings → Click Casting)

## Philosophy

HoverCasts intentionally does **one thing well**:
show you what will happen *before* you click.

No configuration UI, no profiles, no reinvention of click-casting—just visibility.

## License

MIT (or update if you prefer a different license).
