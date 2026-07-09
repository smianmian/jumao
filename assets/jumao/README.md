# Jumao Mascot Asset System

This folder is the source of truth for Jumao mascot assets.

## Visual Rules

- Pixel art only: use hard rectangular edges and integer grid coordinates.
- Color assets use a transparent square canvas.
- Main color is orange, with preserved ears, forehead stripes, tail, eyes, and nose.
- Do not add blur, drop shadow, soft lighting, or complex gradients.
- Template assets must use only black and transparency. They must not depend on color to show state.

## Source

- The color mascot assets are source-derived from the Jumao reference image used during asset preparation.
- The raw `image.png` reference file is intentionally not included in this folder or the npm package.
- `color/jumao-cat.svg` and `state/color/*.svg` are pure SVG rectangle geometry on a 64 x 64 pixel grid.
- PNG files are exported from the same rectangle grid with nearest-neighbor scaling.
- Do not replace the rectangle source with embedded screenshots, base64 images, filters, shadows, or gradients.
- `menubar/*.svg` and `state/template/*.svg` use a dedicated 22px black template glyph so menu bar icons stay readable at 16px to 22px.

## Terminal ASCII

- Default files in `ascii/` are pure ASCII and safe for terminals, CI logs, and SSH.
- Keep each line between 32 and 48 characters.
- Optional ANSI orange wrapper for capable terminals:

```text
\x1b[38;5;208m<ASCII CONTENT>\x1b[0m
```

## State Semantics

- `ready`: normal open eyes, raised tail.
- `blocked`: blocked/error state, x eyes or warning mark, lowered tail.
- `checking`: focused eyes, three scan dots.
- `sleeping`: closed eyes and low energy. `zZ` appears only in color or ASCII assets.
- `copied`: happy squint eyes with a paper/check mark.

State priority:

```text
blocked > checking > copied > sleeping > ready
```

`copied` is transient. Show it for 1.2 to 1.8 seconds, then return to the previous non-copied state.

## Usage

- `color/jumao-cat.svg`: primary source icon for README, website, popovers, npm, and GitHub Releases.
- `color/jumao-cat-*.png`: exported transparent PNG sizes.
- `menubar/*-template.svg`: macOS menu bar template icons.
- `state/color/*.svg`: colored state icons.
- `state/template/*.svg`: black template state icons for tinted UI contexts.
