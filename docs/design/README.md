# Swoop design

Swoop's visual design guidance: the brand, the design system and user journeys. The written spec (tokens,
components, rules) is [`../DESIGN.md`](../DESIGN.md); this folder holds the visual material behind it.

```
docs/design/
├── README.md                 This index
├── design-system.html        Visual design system: themes, color, type, shape, components
├── journeys.html             User journeys, from first launch to updates
├── style.css                 Shared styles for the two pages above
└── brand/                    Logo: app icon, menu bar glyph, construction, usage, archive
    ├── README.md
    ├── icon/                 Current app icon master (1024 px)
    ├── menu-bar/             Current menu bar glyph (template + update) and the SVG for web pages
    └── archive/              Retired logos, kept so we can bring them back if needed
```

## Rules

- **Design material lives here,** not on the Desktop or in a scratch directory.
- **No loose files.** Every file belongs to a section above and is referenced from that section's README.
- **When the logo changes,** update the shipped assets (see [`brand/README.md`](brand/README.md)),
  [`../DESIGN.md`](../DESIGN.md), and move the retired version to `brand/archive/`.
- **No private content:** no screenshots of a real desktop or other people's content.
