# Working on Slayer Revo together

How the project is set up, how to get it running on your computer, and how we share work
without overwriting each other.

## How it fits together

- **The code lives in files, not in Studio.** Every script is a `.luau` file in `src/`. We edit
  them in VS Code.
- **Rojo** copies those files into Roblox Studio. While it's connected, every time you save a
  file, the script updates in Studio within a second.
- **GitHub** is how we share code. You push your changes, the other person pulls them.
- **Team Create** (the shared Studio place) is for multiplayer testing, building things by hand,
  and publishing the real game. It is *not* where we write scripts.

```
You:    your files → your rojo serve → your own local place  (test alone)
Friend: their files → their rojo serve → their own local place  (test alone)
                ↕  shared through GitHub  ↕
             main → synced into Team Create → published game
```

Rojo only works for **one person per place**. If two people connect Rojo to the same Team
Create place, they overwrite each other's scripts. So each of us connects Rojo to our **own
local copy** of the place, and only one person syncs into Team Create.

## One-time setup

### 1. Install the tools

- **Git**: <https://git-scm.com/downloads> (on Windows, this also gives you *Git Bash*)
- **VS Code**: <https://code.visualstudio.com>
- **Rokit** (installs Rojo and StyLua at the exact versions this project uses):
  - Mac / Linux:
    ```bash
    curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
    ```
  - Windows (PowerShell):
    ```powershell
    Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
    ```
  - Close and reopen your terminal afterwards.

> There is no `package.json` and no `npm install`. This isn't a Node project. The only
> "dependencies" are the tools in `rokit.toml`, and `rokit install` gets them.

### 2. Get the project

```bash
git clone https://github.com/amirchoo/SlayerRevo.git
cd SlayerRevo
rokit install
```

If Rokit asks whether to trust `rojo` or `StyLua`, answer yes.

### 3. Install the Rojo plugin in Studio

```bash
rojo plugin install
```

Restart Studio. A **Rojo** button appears in the Plugins tab.

### 4. Make your own local place

```bash
rojo build -o SlayerRevo.rbxlx
```

This builds a fresh place file from everything in the repo: all scripts, remotes, and the town
models in `assets/town`. The town is built by code when the game starts, so pressing Play gives
you the full game.

`SlayerRevo.rbxlx` is in `.gitignore`, so it stays on your computer and never conflicts with
anyone.

**If Team Create has hand-built things** (terrain, parts placed by hand) that aren't in the
repo, copy the Team Create place instead:

1. Open the Team Create place in Studio.
2. **File → Save to File As…** → save as `SlayerRevo.rbxlx` inside your `SlayerRevo` folder.
3. Close it and open that local file. It's now your own offline copy.
4. Connect Rojo (below). It replaces the scripts with the current files and leaves the
   hand-built stuff alone.

Repeat this whenever new hand-built things are added to Team Create.

## Every day

### Start working

```bash
cd SlayerRevo
git checkout main
git pull                          # get everyone's latest work
git checkout -b my-feature        # a new branch for what you're doing, e.g. "dash-combo"
rojo serve
```

Open **your local `SlayerRevo.rbxlx`** in Studio (double-click it, or File → Open from File;
*not* the Team Create place), then click **Rojo → Connect**.

### Write and test

1. Edit scripts in `src/` in VS Code.
2. Save. The change shows up in Studio immediately.
3. Check for syntax errors (one broken script can stop every script from loading):
   ```bash
   sh tools/check_syntax.sh
   ```
   On Windows, run this in **Git Bash**.
4. Press **Play** in Studio to test.

Only you can see this. Nothing reaches GitHub or Team Create until you push.

### Share your work

```bash
git add -A
git commit -m "Add dash combo to the spear"
git push -u origin my-feature
```

Then on GitHub, open a **Pull Request** from your branch into `main`. Once it's merged, the
other person runs `git pull` and their Rojo picks up your code right away.

### Getting work into Team Create / the live game

One person (Amir) does this, so only one Rojo ever touches Team Create:

1. `git checkout main && git pull`
2. Open the Team Create place, `rojo serve`, **Connect**.
3. Test it there, then publish.

## Testing together

Use Team Create for anything multiplayer: open the Team Create place and use
**Test → Team Test** so we're both in the same server. You don't need Rojo connected to test,
only to sync new code in.

## Coding live together (optional)

If we're both online and want to edit the same code at the same time, use **VS Code Live
Share** instead of branches:

1. Both install the **Live Share** extension in VS Code.
2. The host (Amir) opens the folder and clicks **Live Share → Share**, then sends the link.
3. The guest opens the link and edits the host's files directly. You see each other's cursors live.
4. Only the host runs `rojo serve`, connected to Team Create. Every save from either person
   shows up there for both of you.
5. At the end, the host commits and pushes.

The guest can only work this way while the host is online.

## Rules

- **Never edit scripts inside Studio.** Rojo overwrites them on the next sync. Always edit the
  files in `src/`.
- **Never connect Rojo to the Team Create place** unless you're the one syncing `main` into it.
- **Pull before you start, push when you're done**, and work on your own branch, not `main`.
- **Say which files you're working on**, especially big ones like `src/server/TownBuilder.luau`,
  so we don't both edit the same lines.
- Read `CLAUDE.md` (project rules) and `docs/design.md` (game direction) before building a new
  system.

## Troubleshooting

| Problem | Fix |
|---|---|
| `npm install` fails / "can't download dependencies" | There's no npm here. Run `rokit install`. |
| `rojo: command not found` | Reopen the terminal after installing Rokit, then `rokit install` in the project folder. |
| Rojo says the port is already in use / already listening | A `rojo serve` is already running on your computer. Close that terminal, or find it with `lsof -i :34872` (Mac) and `kill` it. |
| Rojo plugin won't connect | Make sure `rojo serve` is running and you're in your **local** place, not Team Create. |
| My changes don't show up in Studio | Rojo isn't connected. Run `rojo serve` and click Connect. |
| A script I edited in Studio got reset | Rojo overwrote it. Make the change in the `src/` file instead. |
| Nothing works after I pulled | Run `sh tools/check_syntax.sh` to find a broken script. |
| Git says there's a merge conflict | Open the file in VS Code, choose which version to keep, save, `git add` it, then `git commit`. Ask if unsure. |
