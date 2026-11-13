# Publishing Rubber Dinghy: one-time setup

This file isn't shipped in the addon zip; it's just for you.

## 0. Share it today, no accounts needed
```
powershell -File tools\build_local.ps1 -Version 1.0.0
```
Send friends `dist\RubberDinghyRapidLevelGuide-1.0.0.zip`. They unzip it into
`World of Warcraft\_forever_\Interface\AddOns\`. No automatic updates this way.

## 1. GitHub: automatic releases, and WowUp updates for friends
1. Create an empty repository on github.com, e.g. `rubber-dinghy-rapid-level-guide`. Public is
   easiest for WowUp.
2. In this folder, run:
   ```
   git init -b main
   git add .
   git commit -m "Rubber Dinghy Rapid Level Guide v1.0.0"
   git remote add origin https://github.com/<you>/rubber-dinghy-rapid-level-guide.git
   git push -u origin main
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. The **Actions** tab shows "Package and release" running. When it finishes, the **Releases** page
   has the zip.
4. Friends install it in **WowUp → Get Addons → Install from URL** with the repo's address. From then
   on, every new tag you push (`v1.0.1`, `v1.1.0` and so on) reaches them as an update.

## 2. CurseForge (optional, for the CurseForge app)
1. Go to authors.curseforge.com, then **Create Project → World of Warcraft**. Fill in:
   - **Name:** Rubber Dinghy Rapid Level Guide
   - **Licence:** GNU GPLv3
   - **Category:** Quests & Leveling
   - **Description:** paste the README, keeping the credits section
   - **Logo:** add one
2. Copy the **Project ID** from the project's About box into the TOC, on a new line under
   `## X-Credits`:
   ```
   ## X-Curse-Project-ID: 123456
   ```
3. Create an API token at curseforge.com → Account → API tokens. In GitHub, add it under
   **Settings → Secrets and variables → Actions** as `CF_API_TOKEN`.
4. Push the next tag. The release uploads to CurseForge as well, tagged as Forever (1.60.1).
   Moderators approve the project before it's public. They don't publish a review time; a few days
   is typical.

## 3. Wago Addons (optional)
Create the project on addons.wago.io, add `## X-Wago-ID: <id>` to the TOC and a `WAGO_API_TOKEN`
secret to GitHub.

## Releasing an update
1. Change the code or the route (`tools/gen_route.py`, then rebuild `Data.lua`).
2. Add a line to `CHANGELOG.md`.
3. Commit, then `git tag v1.0.1` and `git push origin main v1.0.1`.

## Rules to keep
- Keep the credits to Questie/QuestieDB and the GPLv3 licence. Never use the Questie name or logo
  for this addon.
- Never commit `Libs/`. The release fetches the official libraries itself.
