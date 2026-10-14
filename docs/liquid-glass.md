# Liquid glass (version 1.5)

How the app's floating layer was rebuilt as liquid glass, and the rules for adding to it.

## Where glass goes

Only things that float over content are glass: the tab bar and the add button, header buttons, the pager in a header, sheets, the workout and rest bars, the plate bar, toasts, chart tooltips and the pull-to-sync circle. Content stays on solid cards, as before. Glass on glass is avoided: a button inside a sheet or a card is a plain control, not another layer of glass.

## The material

One set of tokens, with dark and light values (`--lg-*` in the `:root` blocks):

| Token | What it is |
| --- | --- |
| `--lg-fill` | A clear tint for small controls (the tab bar, header buttons, pagers). |
| `--lg-strong` | A nearly opaque tint for surfaces that hold reading: sheets, floating bars, toasts, tooltips. |
| `--lg-blur`, `--lg-blur-strong` | Blur with extra saturation, so colour behind the glass stays vivid instead of greying out. |
| `--lg-sheen` | Light falling from above: a soft gradient over the top of the fill. |
| `--lg-rim` | The specular rim: a bright edge top-left, a glint bottom-right, a hairline, and an inner glow where the glass is thickest. Inset shadows only, so it needs no pseudo-element (the 44 px tap layer already uses `::after`). |
| `--lg-drop` | Depth under floating glass. |
| `--lg-lens` | The selection lens inside a glass control. |
| `--lg-gloss` | The gloss on the tinted add button. |
| `--lg-edge` | The top of the scroll-edge gradient. |

A new floating control: `background: var(--lg-sheen), var(--lg-fill); box-shadow: var(--lg-rim), var(--lg-drop); backdrop-filter: var(--lg-blur)`. Add it to the Reduce Transparency list.

## Motion

- **Lens.** The selected tab, segment or page sits on a lens that slides to the next one with a slight overshoot and flexes (stretches sideways, then settles) as it moves. `seg()` and pagers in `pageHead` get theirs from `addLens(wrap, index, key)`; a control drawn again within 1.5 s (the screen re-renders after a tap) starts where the last one was and slides on. The tab bar's `.tab-lens` follows `A.tab` through `--i`, and stays on the tab you're in under a pushed page, as iOS does.
- **Minimize.** Scrolling down past the top of a long screen shrinks the tab bar to its icons and the add button with it (`body.dock-min`); any scroll up brings the labels back.
- **Press.** Glass controls swell a little when pressed (scale 1.06). Solid buttons still press in (0.965) and rows still dim.
- Reduce Motion switches all of it off.

## Scroll edges

Headers no longer draw a hard line over content. The tab header (`.minihead`), page headers (`.phead`, once scrolled) and the workout header (`.wk-head`) carry a blurred gradient that fades out with a mask, so content softens as it slides under them. The bottom edge above the tab bar does the same.

## Sheets

Sheets float 8 px in from the edges with 32 px corners, and slide fully out of view when closed.

## Accessibility

- Reduce Transparency: every glass surface turns solid (`--lg-*` become surface colours, no blur).
- Increase Contrast: glass surfaces get an outline.
- Text on glass stays on `--lg-strong` wherever there's more than a label to read.

## What isn't there

Real refraction (content bending at the glass edge) needs SVG filters inside `backdrop-filter`, which WebKit doesn't support, and the iPhone app runs in WebKit. The rim, sheen, inner glow and saturation carry the look instead, the same in Safari and Chrome.
