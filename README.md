# Wallpaper

A native macOS 26 wallpaper app built with SwiftUI + Liquid Glass. Browse, generate,
and set desktop wallpapers — plus a 3D Minecraft character builder.

> Personal / educational / portfolio project. Not affiliated with Mojang or Microsoft.
> See `LICENSE` before redistributing — third-party content is **not** MIT-licensed.

## Features

- **Home** — auto-rotating featured hero (personalized by your search history) + carousels
- **Explore** — search Wallhaven, infinite scroll, full-screen preview, multi-display set
- **Library** — local folder browsing, favorites, collections, auto-rotation, gradient
  generator, time-of-day `.heic` builder, live (video) wallpaper
- **Minecraft** — 2D API renders or a real 3D model with armor, per-piece armor trims,
  textured 3D sword, enchant glint, biome backgrounds, multiple draggable players

## Build

Open `Wallpaper.xcodeproj` in Xcode 26+ and run (target macOS 26). No dependencies.

## APIs / data sources

| Service | Use |
|---|---|
| Wallhaven (`wallhaven.cc/api/v1`) | Wallpaper search/browse |
| Starlight Skins | 2D Minecraft character renders |
| mc-heads.net / Minotar | Player skins / fallback renders |
| misode/mcmeta (GitHub) | Minecraft armor/trim/item textures |

## License

Source code: MIT (see `LICENSE`). Third-party fetched content retains its own
rights and is not covered by this license.
