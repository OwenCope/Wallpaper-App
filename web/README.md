# Wallpaper — Minecraft Studio (Web)

A browser version of the app's Minecraft character builder, rendered with **Three.js**.
Type a username, pick armor + a trim pattern/material, and rotate the 3D character.

## Run locally
The page uses ES modules + `fetch`, so open it through a web server (not `file://`):

```bash
cd web
python3 -m http.server 8000
# open http://localhost:8000
```

## Host free on GitHub Pages
1. Push this `web/` folder (already in the repo).
2. Repo → **Settings → Pages** → Source: *Deploy from a branch* → `main` / `/web` (or move to `/docs`).
3. It'll be live at `https://owencope.github.io/Wallpaper-App/`.

## Notes
- Skins: [Minotar](https://minotar.net) · Armor & trim textures: © Mojang via the
  [misode/mcmeta](https://github.com/misode/mcmeta) mirror (CORS-friendly).
- Not affiliated with Mojang. For personal use.
