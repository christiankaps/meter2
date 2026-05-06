# App Icon Assets

This folder contains the first Meter2 app icon direction.

## Design Direction

The mark uses abstract reading bars and a forecast curve to represent manual meter readings, visualization, and prediction. It intentionally avoids analog meter faces, needles, gauges, or hardware-style dials.

The icon is designed to feel modern, native, data-oriented, and calm:

- Light: bright system-friendly base with blue, teal, and green data accents.
- Dark: deep base with luminous but restrained data accents.
- Tinted: grayscale source artwork intended for tint-based icon treatments.

## Generated Files

The generator creates:

- `AppIconLight.iconset`
- `AppIconDark.iconset`
- `AppIconTinted.iconset`
- `app-icon-light-1024.png`
- `app-icon-dark-1024.png`
- `app-icon-tinted-1024.png`
- `../Assets.xcassets/AppIcon.appiconset`
- `../Assets.xcassets/AppIconDark.appiconset`
- `../Assets.xcassets/AppIconTinted.appiconset`
- `../Assets.xcassets/AppIconVariants.appiconset`

Each `.iconset` folder contains the standard macOS icon PNG sizes from 16 px through 1024 px.
Each `.appiconset` folder contains the same macOS sizes plus Xcode `Contents.json` metadata.
`AppIconVariants.appiconset` combines Light, Dark, and Tinted artwork in one icon set using Asset Catalog appearance metadata.

## Regeneration

Run:

```bash
swift scripts/generate_app_icons.swift
```

The source of truth is:

```text
scripts/generate_app_icons.swift
```

## Apple Platform Notes

Apple recommends Icon Composer for modern app icons and appearance variants. These PNGs are intentionally kept portable so they can be imported into Icon Composer later, while the generated `.xcassets` folder provides an immediately consumable Asset Catalog structure for a native macOS target.

Use `AppIconVariants` as the app icon source when the project should consume the Light, Dark, and Tinted variants together. Use `AppIcon`, `AppIconDark`, or `AppIconTinted` only when a single standalone icon set is needed for tooling, previews, or experiments.
