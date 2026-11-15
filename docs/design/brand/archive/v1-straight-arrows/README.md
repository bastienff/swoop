# Archived logo: v1, straight arrows

<img src="icon-1024.png" width="128" alt="Swoop v1 app icon"> <img src="menubar-template.png" width="36" alt="v1 menu bar glyph"> <img src="menubar-update.png" width="36" alt="v1 menu bar glyph, update available">

Swoop's first logo (2026-11-12 to 2026-11-15): two straight, flat swap arrows, → solid white on top and ←
80 % white below, on the same orange squircle. Replaced by the current logo because the arrows felt
generic.

| File | What |
|---|---|
| `icon-1024.png` | App icon master, 1024 px |
| `menubar-template.png`, `menubar-update.png` | Menu bar glyph, normal and update available (18 pt @4x) |
| `swoop-glyph.svg` | The arrows as an 18 × 18 SVG, as used in the design pages |
| `make_icon.swift` | The generator that produced the icon set. Usage: `swift make_icon.swift <appiconset dir>` |

To restore it: run the archived `make_icon.swift` on the app icon set, bring back the straight-arrow
`statusImage` from git history (before 2026-11-15), and paste `swoop-glyph.svg` back into the design pages.
