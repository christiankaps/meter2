# App Icon Assets

This folder contains the Meter2 app icon direction used by the macOS app.

## Design Direction

The mark uses a simplified household meter and restrained statistics elements to represent manual meter readings, visualization, and prediction.

The icon is designed to feel modern, native, data-oriented, and calm:

- Light: system-friendly base with green and red utility accents.
- Dark: currently uses the same source artwork until a dedicated dark appearance is designed.
- Tinted: currently uses the same source artwork until a dedicated tint source is designed.

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
`AppIconVariants.appiconset` is the active macOS app icon set and uses the light artwork. The standalone dark and tinted sets are kept for tooling, previews, and future appearance-specific artwork.

## Regeneration

Run:

```bash
swift scripts/generate_app_icons.swift
```

The source of truth is:

```text
Resources/AppIcon/app-icon-light-1024.png
Resources/AppIcon/app-icon-dark-1024.png
Resources/AppIcon/app-icon-tinted-1024.png
```

`scripts/generate_app_icons.swift` resizes those source images into all required macOS asset slots.

## Apple Platform Notes

Apple recommends Icon Composer for modern app icons and appearance variants. These PNGs are intentionally kept portable so they can be imported into Icon Composer later, while the generated `.xcassets` folder provides an immediately consumable Asset Catalog structure for a native macOS target.

Use `AppIconVariants` as the app icon source for the app target. Use `AppIcon`, `AppIconDark`, or `AppIconTinted` only when a single standalone icon set is needed for tooling, previews, or experiments.
