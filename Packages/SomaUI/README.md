# SomaUI

The Soma design system: the tokens every surface reads from, and the components
built on top of them.

## Products

| Product | Ships | Holds |
|---|---|---|
| `SomaUI` | yes | theme, tokens, components |
| `SomaUIPreviewSupport` | no | sample fixtures for `#Preview` and the gallery |

`SomaUIPreviewSupport` is linked only by development surfaces (the component
gallery, previews). Nothing user-facing should import it.

## The theme

The look is one `Sendable`, `Equatable` value, injected through the environment:

```swift
WindowGroup {
    ContentView()
        .somaTheme(.standard)
}
```

Components read it with `@Environment(\.somaTheme)`. They never take colours,
copy or measurements as parameters, so a screen, a sheet or a single card can be
re-branded without touching any call site below it.

`SomaTheme` is a struct rather than a protocol on purpose: reading a token is a
field access instead of a witness-table call, and the whole theme compares in one
`==`, so an unchanged subtree is skipped wholesale.

`.standard` is the app's look on the website, the `--app-*` variables in the
landing page's `app/globals.css`: a warm near black ground in dark, a near white
in light, and one champagne accent. It is the only theme the package ships. A
variant is a copy with edits: the structure, the components and the metrics stay
shared:

```swift
var variant = SomaTheme.standard
variant.colors.accent = SomaColorValue(light: 0x2F6F5F, dark: 0x6EB0A0)
variant.metrics.accessoryDiameter = 64
```

Or, for the common case: `SomaTheme.standard.withAccent(...)`.

Light and dark are not two themes. Every colour carries both appearances, and
the system's colour scheme, which an app may force, picks the one that draws.

## One family

`SomaFontFamily` has one case, and `SomaFontSpec` can name nothing else:

| Family | Face | Carries |
|---|---|---|
| `.pro` | SF Pro | words and numbers alike |

The website sets Geist for its headlines and its figures. SF Pro is the system
face closest to it, and it is set the same way: regular weight, tight tracking.
A face is a type rather than a convention, so a second one cannot arrive by
adding one more token, only by editing the enum.

Numbers hold their columns through the role, not the family: `metric` and
`rowValue` carry `digits: .tabular`, and every other role keeps the face's
natural spacing.

A role is a font and its tracking, applied together:

```swift
Text(title).somaFont(theme.typography.display)
```

Setting `.font(spec.font)` alone draws the role without its tracking.

## Touch and pointer

`SomaMetrics` and `SomaTypography` each ship two scales, and `.standard`
resolves to the right one at compile time:

| | `.touch` (iOS, iPadOS) | `.pointer` (macOS) |
|---|---|---|
| Smallest target | 44pt | 24pt |
| Tab height / glyph | 46 / 19 | 32 / 15 |
| Accessory | 58pt | 40pt |
| Body / title / display | 16 / 22 / 34 | 13 / 17 / 26 |

A cursor hits a small target precisely and a Mac reads at desk distance, so the
whole chrome tightens instead of carrying finger-sized slack onto a desk. A
phone scale rendered in a window reads as shouting.

Override either scale on a theme when a surface needs the other:
`theme.metrics = .pointer`.

## Across form factors

The bar has one adaptive behaviour, driven by the horizontal size class rather
than by a device check: so it answers correctly for a phone, a folded cover
screen, an unfolded foldable, an iPad in Slide Over, and a resized Mac window
alike, and it re-answers live when the width changes under it.

| Platform / width | Placement | Shape |
|---|---|---|
| Compact (phone, folded cover screen) | `.bottom` | floating glass bar, spans the row |
| Regular (iPad, unfolded phone, landscape) | `.topCentered` | floating glass bar, hugs its labels, capped at `barMaxWidthRegular` |
| macOS | `.sidebar` | a persistent column, wrapped in a `NavigationSplitView` |

The Mac does not get a floating bar. A bar across the top of a window spends the
vertical room a desktop window has least of, and duplicates a job the sidebar
already does natively: so `.sidebar` takes the same items, the same selection
binding and the same living accessory and lays them out the way the platform
expects. Pass `placement:` to override on any surface.

Install it with the modifier, which picks the safe-area edge for you:

```swift
page.somaTabBar(items: tabs, selection: $selection) {
    SomaPulseAccessory(accessibilityLabel: "Ask Soma") { isAsking = true }
}
```

Force a placement with `placement:` when a surface needs one specific shape.

On macOS there is no size class to read, and the answer is `.sidebar` regardless
of width.

## Layout

```
Sources/SomaUI/
  Tokens/       SomaColorValue · SomaColors · SomaTypography · SomaMetrics · SomaMotion
  Theme/        SomaTheme · the environment key and the .somaTheme(_:) modifier
  Components/
    Chrome/     SomaTabItem · SomaTabBarPlacement · SomaGlassTabBar ·
                SomaPulseAccessory · View+SomaTabBar
    Containers/ SomaCard
    Controls/   SomaGlassPressStyle · SomaSegmentedControl
    Identity/   SomaMark
```

`SomaColorValue` is the one place in the system where a raw colour is written.
Nothing else spells a colour out.

## House rules these components follow

- **Glass is chrome, and it is inert.** Interactive glass swallows the tap meant
  for the button under it. Press feedback is a scale plus a dim, off the theme.
- **One accent.** It carries action, selection and state: never decoration, and
  never more than a fraction of the screen. Selection is a tonal capsule; the
  accent rides the glyph and the label.
- **Tonal before shadow.** Surfaces separate by stepping up a tone.
- **Every animation has a still counterpart.** Reduce Motion stops the spin and
  the breath and settles the glow.
- **Nothing is page-bound.** A component is driven entirely by its inputs and the
  theme, holds no copy of its own, and never reaches back into a parent's state.
- **A component ships with a `#Preview` and a gallery entry**, both fed from
  `SomaPreviewSamples` rather than inline fixtures.

## Accessibility

Tabs expose `.isSelected`, every control clears the 44pt floor, and at
accessibility type sizes the bar drops its labels and grows the glyphs rather
than letting the row overflow: the same trade the system tab bar makes.

## Verify

```bash
swift build && swift test
```
