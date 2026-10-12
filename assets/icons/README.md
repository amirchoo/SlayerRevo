# HUD icons

Every icon in the HUD comes from [game-icons.net](https://game-icons.net). They're drawn onto one
sprite sheet (`atlas.png`), which is uploaded to Roblox as a single image. Code uses icons by name
through `src/shared/Icons.luau`; `icons.json` maps each name to its game-icons.net file.

## Adding or changing an icon

1. Find one on game-icons.net and note its author and name from the URL
   (`game-icons.net/1x1/lorc/crossed-swords.html` gives `lorc/crossed-swords`).
2. Add `"MyIcon": "author/name"` to `icons.json`.
3. Get the icon files: download https://github.com/game-icons/icons/archive/refs/heads/master.zip
   and unzip it somewhere outside the repo.
4. `python3 tools/icon_atlas.py <unzipped icons-master folder>` rebuilds `atlas.png` and
   `src/shared/IconAtlas.luau`.
5. Upload `atlas.png` to Roblox (Studio: Asset Manager > Import, or the Studio MCP
   `upload_image` tool), then put the new asset id in `Icons.IMAGE` in `src/shared/Icons.luau`.

## Credits (required)

The icons are licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/): the game must
credit them, e.g. in its description: "Icons by Lorc, Delapouite, Skoll, sbed, John Redman,
Carl Olsen, Zeromancer, Priorblue and others from game-icons.net (CC BY 3.0)."
