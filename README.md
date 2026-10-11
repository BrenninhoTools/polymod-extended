# polymod-extended

An expanded modding framework for Haxe games, built on top of [Polymod](https://github.com/larsiusprime/polymod).

polymod-extended keeps Polymod as the engine underneath and adds a management layer on top of it:

- Mods packed as `.zip` or `.rar` files, loaded straight from the archive
- An ordered mod list you can save and restore, with enabling, disabling and reordering at runtime
- Extra mod options in `_polymod_meta.json`: priority, load order rules, incompatibilities, platform and game version filters, tags, custom data and user settings
- Automatic saving of the mod list and mod settings
- A web API for HTML5 builds: mods from URLs, uploads, drag and drop, and mods kept in the browser
- A desktop API: install, uninstall, export and create mods, open the mods folder and reload when files change
- Folder organization: categories as subfolders, a standard mod structure with validation, folder mapping between engines (Psych, V-Slice, Codename) and automatic file organizing
- Mods from links: GameBanana, GitHub, Google Drive, Dropbox, MediaFire and direct URLs, with update checks
- Mods that change the game: allowed app settings (title, icon, FPS, window) and an event hook system for scripts
- Several mod folders at once and the right default mods folder for each platform
- An image API (overrides by load order, aliases, Sparrow/Packer/JSON/Animate atlases, validation) and an HScript API (per-mod scripts in a sandbox)
- One-call reloading, a central error log and signals your game can listen to

## Installation

polymod-extended targets Polymod 2.0, which is currently only available from git, and uses [hscript](https://github.com/HaxeFoundation/hscript) for mod scripts.

```bash
haxelib git polymod https://github.com/larsiusprime/polymod
haxelib install hscript
haxelib git polymod-extended https://github.com/BrenninhoTools/polymod-extended
```

Then add it to your `Project.xml`:

```xml
<haxelib name="polymod-extended" />
```

Or to your `.hxml`:

```hxml
-lib polymod-extended
```

## Quick start

```haxe
import polymod.Polymod.Framework;
import polymod.extended.PolymodExtended;

class ModHandler
{
	public static function init():Void
	{
		PolymodExtended.onError.add(error -> showError(error.message));

		PolymodExtended.init({
			modRoot: "mods",
			framework: Framework.FLIXEL,
			gameVersion: "1.0.0",
			modListFile: "mods/modlist.json",
			settingsFile: "mods/settings.json"
		});
	}

	public static function toggle(id:String):Void
	{
		PolymodExtended.setModEnabled(id, !PolymodExtended.modList.isEnabled(id), true);
	}
}
```

`showError` is yours to implement. With `modListFile` and `settingsFile` set, the mod list and settings are loaded on `init` and saved whenever they change (on targets with file access). You can also pass your own `ModList` and `ModSettings` and save them with `toJson()` wherever you want (`FlxSave`, `SharedObject`, etc).

## Archive mods

On native targets (Windows, Mac, Linux, Android, iOS, HashLink), every `.zip` and `.rar` file inside the mod folder is mounted as a mod folder with the same name. `mods/cool_mod.zip` behaves exactly like a `mods/cool_mod/` folder. Files are read on demand, nothing is extracted to disk.

- The archive can have `_polymod_meta.json` at its root, or a single folder at the root that contains it (what you get when zipping a folder).
- `__MACOSX/`, `.DS_Store`, `Thumbs.db` and `desktop.ini` are ignored.
- If a folder and an archive have the same name, the folder wins and a warning is logged.
- An archive with any file that cannot be read is skipped as a whole, with an error explaining why.

| Format | Supported |
| --- | --- |
| ZIP | Store and Deflate (the default of every zip tool). No encryption, no ZIP64. |
| RAR 4 / RAR 5 | **Store method only.** When creating the archive in WinRAR, set "Compression method" to "Store". Compressed, encrypted and multi-volume RARs are rejected with a clear error. |

RAR compression is a proprietary algorithm with no Haxe implementation, so only uncompressed RAR archives can be read on every platform.

Archives can also be mounted from memory, for example after a download:

```haxe
var fs = cast(PolymodExtended.fileSystem, polymod.extended.fs.ArchiveFileSystem);
fs.mountBytes(downloadedBytes, "downloaded_mod.zip");
PolymodExtended.reload();
```

Set `archives: false` in the config to turn archive loading off. New archive formats can be added with `ArchiveFormats.register`.

## Web (HTML5)

Browsers have no mods folder, so on HTML5 `PolymodExtended.init` uses a `VirtualFileSystem` that keeps mods in memory. `WebMods` fills it:

```haxe
import polymod.Polymod.Framework;
import polymod.extended.PolymodExtended;
import polymod.extended.web.WebMods;

PolymodExtended.init({framework: Framework.OPENFL, modListFile: "modlist.json", settingsFile: "settings.json"});

WebMods.restoreInstalled().then(_ -> WebMods.loadIndex("mods/index.json"));
```

| Function | Description |
| --- | --- |
| `loadUrl(url, ?dirName, install, ?options)` | Downloads a `.zip` or `.rar` (or any supported link, see Mods from links) and loads it. With `install: true` it is also kept in the browser. |
| `loadIndex(url, install)` | Loads every mod listed in a JSON index, see below |
| `openFilePicker(multiple)` | Opens the browser file picker and installs the chosen archives. Call it from a click or key press. |
| `enableDropZone(?element)` | Installs archives dropped on the page (or on `element`). Returns a function that turns it off. |
| `installBytes(bytes, name)` / `installBlob(file)` | Installs an archive you already have |
| `restoreInstalled()` | Loads every mod the player installed before. Call it once at startup. |
| `uninstall(dirName)` / `clearInstalled()` / `listInstalled()` | Manages installed mods |
| `checkUpdates()` / `updateInstalled(dirName)` | Checks and updates mods installed from links |
| `exportInstalled(dirName)` / `saveFile(bytes, name)` | Gets an installed archive back and offers it as a browser download |
| `createBackup()` / `restoreBackup(bytes)` | One `.zip` with every installed mod, the mod list and the settings |
| `getStorageEstimate()` / `requestPersistentStorage()` | Browser storage usage, and asking the browser not to clear it |
| `clearCache()` | Forgets cached downloads |
| `onInstalled` / `onUninstalled` / `onLoadFailed` / `onProgress` / `onStorageWarning` | Signals |

`loadUrl` options: `install`, `dirName`, `cache` (default `WebMods.cacheDownloads`), `maxBytes` (default `WebMods.maxModSize`, 256 MB), `fileIndex` / `fileName` (which file of a GameBanana page or GitHub release), `onProgress` and `onStart`. `onStart` receives the `WebDownload`, which has `cancel()`, `loaded` and `total`. `WebDownload.cancelAll()` stops every download.

```haxe
WebMods.loadUrl("https://gamebanana.com/mods/123456", null, true, {
	onProgress: progress -> loadingBar.value = progress.ratio,
	onStart: download -> cancelButton.onClick = download.cancel
});
```

Downloads are cached in IndexedDB together with their `ETag`/`Last-Modified`, so loading the same URL again only asks the server whether it changed, and works offline. Installs fail with a clear message when a mod is over the size limit or the browser has no room left, and `onStorageWarning` fires once usage passes `storageWarningRatio` (90%). GameBanana checksums are verified after downloading.

Installed mods are stored in IndexedDB, so they survive page reloads. The mod list and settings go to `localStorage` under the names given in `modListFile` and `settingsFile`. All functions return promises and reload the mods when they finish (set `WebMods.autoReload = false` to reload yourself).

A mod index is a JSON file with URLs relative to the index itself:

```json
{
  "mods": [
    "cool_mod.zip",
    { "url": "packs/song_pack.rar", "name": "song_pack" }
  ]
}
```

Mods that are not archives can be added from code with `VirtualFileSystem.addFolderMod(dirName, files)`.

Note: in our tests, the current Polymod git version fails to compile for HTML5 because some `#if html5` blocks in its HScript interpreter are also compiled inside macros. If you hit `Type not found : HxOverrides`, change those lines to `#if (html5 && !macro)`, as the web job in `.github/workflows/test.yml` does.

Dropping a link (for example from a GameBanana page) on a drop zone installs it like a dropped file.

## Mods from links

`ModSources` turns a share link into a direct download. It is used by `WebMods.loadUrl` on the web and `RemoteMods.install` on native targets:

| Site | Accepted links |
| --- | --- |
| GameBanana | Mod pages (`gamebanana.com/mods/123`), sound and WiP pages, `gamebanana.com/dl/...` links and 1-click links (`yourgame:https://gamebanana.com/mmdl/...,Mod,123`). Uses the GameBanana API to pick the file, skips archived files and files that did not pass GameBanana's antivirus, and checks the MD5. |
| GitHub | Repositories (latest release, or the default branch zip when there are no releases), release pages, `releases/download` links and branch links (`/tree/branch`) |
| Google Drive | File share links (`/file/d/ID/view`, `open?id=ID`) |
| Dropbox | Share links (`dl=0` becomes `dl=1`) |
| MediaFire | File pages, the real download link is read from the page |
| Anything else | Used as a direct download |

When a page has several files, the first `.zip`/`.rar` is used; pass `fileName` or `fileIndex` to choose. Links to `.7z` and other formats are refused with a message saying which formats work. Add your own site with `ModSources.register(source)`.

On native targets:

```haxe
import polymod.extended.desktop.RemoteMods;

RemoteMods.onProgress.add(progress -> loadingBar.value = progress.ratio);
RemoteMods.installAsync("https://gamebanana.com/mods/123456", {category: "songs"}, result ->
{
	if (!result.success)
		showError(result.error);
});
```

| Function | Description |
| --- | --- |
| `install(link, ?options)` | Downloads and installs, blocking until it finishes |
| `installAsync(link, ?options, ?onDone)` | Same in a background thread; `onDone` and `onProgress` run on the main thread during `DesktopMods.update(elapsed)` (or `RemoteMods.update()`) |
| `cancel()` | Stops the current download |
| `resolve(link)` | Only finds the direct link and file details |
| `getSource(id)` | Where an installed mod came from |
| `checkUpdates(?ids)` / `updateMod(id)` | Compares with the site (file id, version or date) and reinstalls in place, keeping the category |

Options: `category`, `replace`, `reload`, `enable`, `fileIndex`, `fileName`, `maxBytes` (default `RemoteMods.maxModSize`, 512 MB). Downloads go to `mods/.downloads` and are removed after installing; sources are saved in `mods/.sources.json`.

Browsers block downloads from most of these sites unless they send CORS headers, and many file hosts (including the ones above) do not send them for their downloads. For HTML5 builds, set `ModSources.corsProxy` to a proxy you control (`"https://your-proxy/?url="` or a template with `{url}`). It is only used for the hosts in `ModSources.proxyHosts`, or for every request with `ModSources.proxyAll`.

## Mods that change the game

### App settings

Mods can change a few app settings through an `app` block in `_polymod_meta.json`, but only the ones the game allows:

```json
{
  "app": { "title": "Funkin' Remix", "icon": "icon.png", "fps": 144, "backgroundColor": "#1A1A2E" }
}
```

```haxe
PolymodExtended.init({allowAppSettings: true});
ModAppSettings.allow("noteSkin", {type: STRING, maxLength: 32});
ModAppSettings.onChanged.add(values -> applyMyGameSettings(values));
```

`allowAppSettings: true` (or `ModAppSettings.allowDefaults()`) allows `title`, `icon` (a PNG inside the mod), `fps` (30 to 360), `width`, `height`, `fullscreen`, `antialiasing` and `backgroundColor`. Types are `string`, `int`, `float`, `bool`, `color` and `file`, with optional `min`, `max`, `maxLength` and `extensions`. Values outside the range are clamped, invalid values and keys the game did not allow are ignored with a warning, and the last loaded mod wins when two mods set the same key. On Lime targets the title, icon, FPS, size and fullscreen are applied to the window and restored when the mods are disabled; everything else is up to the game through `onChanged`, `get(key)` and `getSource(key)`.

### Hooks

`ModHooks` is an event bus between the game and mod scripts:

```haxe
var event = ModHooks.call("noteHit", {note: note, player: true});

if (event.cancelled)
	return;
```

```haxe
ModHooks.add("noteHit", event -> event.data.note.alpha = 0.5, "my_mod", 10);
```

Listeners run from highest to lowest priority. `event.cancel()` marks the event as cancelled (unless the game called it with `cancelable: false`), `event.stopPropagation()` skips the remaining listeners and `event.result` can carry a value back. A listener that throws is logged and, after `ModHooks.maxErrors` errors, removed, so a broken script does not break the game. Listeners added with a mod id are cleared on every reload; the game's own listeners stay. `modsLoaded` is called after every load. With `useScriptedClasses: true`, `ModHooks` and `ModEvent` are imported automatically in Polymod scripted classes.

## Mod folders

### Several roots

```haxe
import polymod.extended.util.ModPaths;

var roots = ModPaths.defaultRoots("My Game");
PolymodExtended.init({modRoot: roots[0], modRoots: roots.slice(1)});
```

Mods from `modRoots` are loaded as if they were in `modRoot`: categories with the same name are merged, and when a mod folder exists in more than one root the first one wins with a warning. Installing, creating and moving mods use `modRoot`; uninstalling, organizing and opening folders find the real folder in any root, and the watcher watches every root.

### Default folders per platform

| Function | Result |
| --- | --- |
| `ModPaths.bundledRoot()` | `mods` next to the executable on desktop (outside the `.app` on macOS), `null` on mobile |
| `ModPaths.userRoot(game, ?company)` | Windows `%APPDATA%/[company/]game/mods`, macOS `~/Library/Application Support/game/mods`, Linux `$XDG_DATA_HOME` or `~/.local/share/game/mods`, Android `/storage/emulated/0/Android/data/<package>/files/mods`, iOS the app's Documents folder |
| `ModPaths.androidSharedRoot(name)` | `/storage/emulated/0/<name>/mods`, visible to file managers but needs the "all files access" permission on Android 11+ |
| `ModPaths.defaultRoots(game)` | Bundled and user folders, in that order |
| `ModPaths.ensure(path)` / `isWritable(path)` | Creates a folder / checks it can be written |

The Android app folder needs no permission. On iOS, set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in the app's plist so players can reach the folder from the Files app.

### Files in the root of each mod

`ModStructure.requiredRootFiles` and `recommendedRootFiles` (both empty by default, and both readable from JSON) report files missing from the root of a mod, for example `["_polymod_meta.json", "credits.txt"]` and `["_polymod_icon.png"]`. Recommended files are reported with `recommended: true`.

## Desktop

`DesktopMods` adds mod management for games with a real mods folder. Everything except opening folders and drag and drop also works on Android and iOS.

```haxe
import polymod.extended.desktop.DesktopMods;

DesktopMods.enableDropInstall();
DesktopMods.startWatching(2.0);

override function update(elapsed:Float)
{
	super.update(elapsed);
	DesktopMods.update(elapsed);
}
```

| Function | Description |
| --- | --- |
| `installMod(path, ?options)` | Copies a `.zip`, `.rar` or mod folder into the mods folder and reloads. Options: `replace`, `reload`, `enable`. Returns `{success, id, path, error}`. |
| `uninstallMod(id)` | Deletes the mod's folder or archive and reloads |
| `exportMod(id, destination)` | Packs a folder mod into a `.zip` (archive mods are copied as they are) |
| `createMod(id, ?options)` | Creates a mod folder with `_polymod_meta.json` and empty `data`, `images` and `sounds` folders. Options: `title`, `description`, `author`, `apiVersion`, `modVersion`, `folders`, `extra`. |
| `openModsFolder()` / `openModFolder(id)` | Opens the folder in Explorer, Finder or the Linux file manager |
| `getModLocation(id)` / `isArchiveMod(id)` | Where a mod lives on disk |
| `startWatching(interval)` / `update(elapsed)` / `stopWatching()` | Checks the mods folder for changes and reloads automatically. Call `update` every frame. |
| `enableDropInstall(?options)` | Installs files dropped on the game window (Lime desktop builds) |
| `onInstalled` / `onUninstalled` / `onModsChanged` | Signals |

Installing checks the archive before copying it: unreadable RARs, archives without `_polymod_meta.json` and mods whose id is already installed are refused with a clear `error` message. The watcher ignores the saved mod list and settings files, so saving does not trigger a reload.

## Folder organization

### Categories

Mods can be grouped in subfolders of the mods folder. Any folder without `_polymod_meta.json` is a category, and the mod folders and archives inside it are loaded like any other mod:

```
mods/
  my_mod/
  songs/
    _category.json
    week_pack/
    remixes.zip
  skins/
    pixel_bf/
```

`_category.json` is optional: `{"title": "Song Packs", "description": "...", "order": 1, "hidden": false, "data": {}}`. A mod can also declare `"category": "Skins"` in its metadata to join a category without moving folders (the folder wins when both exist). Categories go one level deep.

```haxe
for (category in PolymodExtended.categories)
	addMenuSection(category.title, PolymodExtended.getModsInCategory(category.id));
```

| Member | Description |
| --- | --- |
| `categories` | All categories, sorted by `order` and title |
| `getCategory(id)` / `getModCategory(modId)` | Lookups |
| `getModsInCategory(id)` / `getUncategorizedMods()` | Mods per category |
| `DesktopMods.createCategory(name, ?title, ?description, ?order)` | Creates a category folder with `_category.json` |
| `DesktopMods.moveModToCategory(id, category)` | Moves a mod folder or archive, `null` moves it back to the root |
| `installMod(path, {category: "songs"})` / `createMod(id, {category: "songs"})` | Install or create straight into a category |

Two mods with the same id are not loaded twice: the first one found wins (root folder before categories) and a warning is logged.

### Mod structure and validation

Give the config a `ModStructure` to define which folders a mod may have and which file types go in each one:

```haxe
import polymod.extended.structure.StructurePresets;

PolymodExtended.init({structure: StructurePresets.vslice()});

for (issue in PolymodExtended.getStructureIssues("my_mod"))
	showIssue(issue.message, issue.suggestion);
```

Presets: `generic()`, `psych()`, `vslice()` and `codename()`. They are starting points based on each engine's usual folders, so adjust them to your engine. A structure can also be loaded with `ModStructure.fromJson`:

```json
{
  "name": "my-engine",
  "folders": [
    { "path": "data", "extensions": ["json", "xml"], "required": true },
    { "path": "images", "extensions": ["png", "xml"], "template": true },
    "scripts"
  ],
  "rootFiles": ["_polymod_meta.json", "_polymod_icon.png", "*.md"],
  "allowUnknownFolders": false
}
```

Validation runs on every scan and reports loose files in the mod root, unknown folders, files with the wrong extension for their folder and missing required folders, each with a suggested location. Issues are logged as warnings and never stop a mod from loading. `createMod` uses the structure's template folders. Set `validateStructure: false` to keep the structure for organizing only.

### Folder mapping between engines

A mod made for one engine's folder layout can be read with your game's layout without moving any file. Set `gameLayout` in the config and each mod's layout is detected from its files, or declared with `"layout": "psych"`:

```haxe
PolymodExtended.init({gameLayout: "vslice"});
```

With that, a Psych mod's `characters/bf.json` can also be read as `data/characters/bf.json`, `weeks/` as `data/levels/`, and a Codename mod's `songs/bopeebo/song/Inst.ogg` as `songs/bopeebo/Inst.ogg`. The original paths keep working.

Built-in layouts are `psych`, `vslice` and `codename`, covering characters, stages, weeks and song audio. Register your own with `FolderLayouts.register(name, [concept => folder])`, override a pair with `layoutMappings`, or map folders per mod:

```json
{
  "folders": { "art": "images", "songs/*/audio": "songs/*" }
}
```

`*` matches one folder name and must appear the same number of times on both sides. Mapping only changes where files are found: JSON, XML and chart formats are not converted between engines. `getModLayout(id)` and `getFolderMappings(id)` show what was applied. Detection can be turned off with `detectLayouts: false`.

### Auto-organize

`ModOrganizer` (native targets) moves misplaced files of a folder mod to the folder its structure suggests:

```haxe
import polymod.extended.desktop.ModOrganizer;

var plan = ModOrganizer.planMod("messy_mod");

for (move in plan.moves)
	showPlannedMove(move.from, move.to);

var result = ModOrganizer.organizeMod("messy_mod");
```

It sends images to `images`, audio to `sounds` (and `Inst`/`Voices` files to `songs`), fonts, videos, scripts and shaders to their folders, and loose JSON, XML and text files to `data`, except atlas files that sit next to an image with the same name, which go with the image. An extra `assets/` folder around the content is removed. Existing files are never overwritten: those moves are listed in `skipped`. Folders left empty are deleted. `planMod` and `planFolder` only report, nothing is moved until `organizeMod`, `organizeFolder` or `apply` runs. Archive mods have to be extracted first.

## Images

`ModImages` finds images in the loaded mods. When several mods have the same image, the one loaded last wins, the same rule Polymod uses for every asset.

```haxe
import polymod.extended.images.ModImages;

if (ModImages.exists("characters/BOYFRIEND"))
{
	var frames = ModImages.getFrames("characters/BOYFRIEND");
	var from = ModImages.getSource("characters/BOYFRIEND");
}
```

Ids are paths inside each mod's `images` folder, with or without `images/` and the extension (`.png`, `.jpg`, `.jpeg`).

| Function | Description |
| --- | --- |
| `resolve(id)` / `exists(id)` / `getSource(id)` | Which mod provides the image and where the file is |
| `getBytes(id)` / `getInfo(id)` | File bytes, and size, type and transparency read from the header without decoding |
| `getAtlas(id)` / `getAtlasText(id)` | The atlas next to the image (`.xml` Sparrow, `.txt` sprite sheet packer, `.json` TexturePacker hash/array or Adobe Animate spritemap), parsed into frames with offsets, rotation, `getAnimationNames()` and `getAnimationFrames(prefix)` |
| `getImage(id)` | `lime.graphics.Image` (Lime) |
| `getBitmapData(id, cache)` | `openfl.display.BitmapData`, cached until the next reload (OpenFL) |
| `getFrames(id)` | `FlxAtlasFrames` built from the image and its atlas (HaxeFlixel) |
| `list(?subfolder)` / `listMod(mod, ?subfolder)` | Image ids from all loaded mods or from one |
| `getOverrides()` | Images provided by more than one mod, and by which ones |
| `validateMod(modId)` | Files that are not real images, images larger than `maxTextureSize` (8192), atlas frames outside their image, broken atlases and atlases without an image |
| `clearCache()` | Runs automatically after every reload |

The atlas is taken from the same mod as the image when it has one, so a mod that only replaces a PNG keeps working with the original atlas. Mods can also redirect images in their metadata:

```json
{
  "images": { "characters/GF": "characters/GF-christmas", "menu/logo": "menu/logo-remix" }
}
```

`ImageAtlas.parse(text)` and `ImageInfo.read(bytes)` work on their own too, on every target.

## Scripts

`ModScripts` runs HScript files from the loaded mods. Turn it on with `scripts: true`:

```haxe
import polymod.extended.scripting.ModScripts;
import polymod.extended.scripting.ScriptSandbox;

ScriptSandbox.expose("FlxG", flixel.FlxG);
ScriptSandbox.exposeClass(flixel.FlxSprite);

PolymodExtended.init({scripts: true});

override function update(elapsed:Float)
{
	super.update(elapsed);
	ModScripts.update(elapsed);
}

function goodNoteHit(note:Note)
{
	if (ModScripts.callStop("onNoteHit", [note]))
		return;
}
```

Every `.hx`, `.hxs` or `.hscript` file directly inside a mod's `scripts` folder is loaded after the mods load, in load order, and `onCreate` is called. On every reload or unload the scripts get `onDestroy` and are thrown away.

```haxe
var hits = 0;

function onCreate()
{
	print("Loaded " + mod.title + " with volume " + mod.getSetting("volume"));
}

function onNoteHit(note)
{
	hits++;
	return note.isBad ? STOP : CONTINUE;
}

hook("songStart", function(event) {
	var song = mod.readJson("data/intro.json");
});
```

| Script global | Description |
| --- | --- |
| `mod` | `id`, `title`, `version`, `path`, `getSetting(key)`, `setSetting(key, value)`, `getData()`, `exists(file)`, `readText(file)`, `readJson(file)` (files inside the mod only) |
| `script` | `name`, `path` and `modId` of the current script |
| `print(...)` | Logs through `ModScripts.onPrint` and the error log |
| `hook(name, callback, ?priority)` | Adds a `ModHooks` listener that is removed with the script |
| `callScripts(name, ?args)` | Calls a function in every loaded script |
| `STOP` / `CONTINUE` | Return values for `callStop` |
| `Math`, `Std`, `StringTools`, `Lambda`, `Date`, `DateTools`, `Json`, `StringBuf`, `EReg`, `ModHooks`, `ModEvent` | Available by default |

| Function | Description |
| --- | --- |
| `call(name, ?args)` | Calls a function in every script, returns the results |
| `callStop(name, ?args)` | Returns `true` as soon as a script returns `STOP` |
| `set(name, value)` | Sets a variable in every script |
| `update(elapsed)` | Calls `onUpdate` |
| `load(path)` / `loadFolder(folder)` | Loads scripts on demand from every mod that has them (for example `stages/week1.hx`), as a `ScriptGroup` with `call`, `callStop`, `set` and `destroy` |
| `destroyGroup(group)` / `destroyAll()` | Unloads scripts |
| `fromString(code, name)` | Runs a script from a string |
| `onError` / `onPrint` | Signals |

Scripts run in a sandbox: they only see the globals above and what the game exposes with `ScriptSandbox.expose(name, value)` or `exposeClass(cls, ?alias)`, and `new` only works for exposed classes. `Type`, `Reflect`, `Sys` and file access are not available unless the game exposes them. Errors (including syntax errors, with line numbers when compiled with `-D hscriptPos`) are caught, logged and sent to `onError`, and a broken script never stops the others. Variables declared at the top of a script keep their values between calls. Scripts cannot be stopped in the middle of an infinite loop, so the game should still only load mods the player chose.

These scripts are separate from Polymod's scripted classes (`.hxc`), which keep working with `useScriptedClasses: true`.

## Mod options

polymod-extended reads extra fields from each mod's `_polymod_meta.json`. Every field is optional.

```json
{
  "id": "my_mod",
  "title": "My Mod",
  "api_version": "0.1.0",
  "mod_version": "1.2.0",
  "dependencies": { "base_mod": ">=1.0.0" },

  "priority": 10,
  "loadAfter": ["other_mod"],
  "loadBefore": ["ui_mod"],
  "incompatible": { "old_mod": "<2.0.0", "broken_mod": "*" },
  "platforms": ["windows", "android"],
  "gameVersion": ">=1.0.0",
  "enabledByDefault": true,
  "hidden": false,
  "tags": ["gameplay", "songs"],
  "data": { "difficulty": "hard", "customMenu": true },
  "settings": [
    { "id": "showIntro", "name": "Show Intro", "type": "bool", "default": true },
    { "id": "lives", "name": "Lives", "type": "int", "default": 3, "min": 1, "max": 9 },
    { "id": "speed", "name": "Speed", "type": "float", "default": 1.0, "min": 0.5, "max": 2.0, "step": 0.1 },
    { "id": "playerName", "name": "Player Name", "type": "string", "default": "BF", "maxLength": 12 },
    { "id": "theme", "name": "Theme", "type": "choice", "choices": ["light", "dark"], "default": "dark" }
  ]
}
```

| Field | Description |
| --- | --- |
| `id` | Always set it explicitly. Dependencies, incompatibilities and load rules are matched by id. |
| `priority` | Integer, default `0`. Mods with a higher priority load later, so their files win conflicts. |
| `loadAfter` / `loadBefore` | Soft ordering rules. Unlike `dependencies`, the other mod does not need to be installed. Circular rules are ignored with a warning. |
| `incompatible` | List of mod ids, or an object of mod ids to version rules (`"*"` means any version). If two loaded mods conflict, the one earlier in the mod list wins and the other is skipped. |
| `platforms` | Platforms the mod runs on: `windows`, `mac`, `linux`, `android`, `ios`, `html5`, or the groups `desktop`, `mobile`, `web`. Prefix with `!` to exclude, like `["!android"]`. |
| `gameVersion` | Semantic version rule checked against `gameVersion` from the config. |
| `enabledByDefault` | Whether the mod starts enabled the first time it is found. |
| `hidden` | Hides the mod from `getVisibleMods()`, for library mods players should not toggle. |
| `tags` | Free-form tags for filtering with `getModsByTag()`. |
| `category` | Category name for mods that are not inside a category folder. |
| `app` | App settings the mod wants to change, see App settings. |
| `images` | Image redirects, see Images. |
| `layout` | Folder layout the mod was made for (`psych`, `vslice`, `codename` or a registered one). |
| `folders` | Extra folder mappings for this mod, see Folder mapping. |
| `data` | Any JSON value, available through `getModData(id)` for your engine to use. |
| `settings` | User-editable options. Types: `bool`, `int`, `float`, `string`, `choice`. Values are validated and clamped. |

Mods that depend on each other are always loaded in dependency order by Polymod. A mod whose dependency is missing is skipped on its own instead of stopping every mod from loading (set `skipDependencyErrors: false` to get Polymod's strict behavior back). Invalid fields never stop a mod from loading, they are reported as warnings.

Reading values in your game:

```haxe
var lives:Int = PolymodExtended.getSetting("my_mod", "lives");
var data = PolymodExtended.getModData("my_mod");

PolymodExtended.setSetting("my_mod", "lives", 5);
PolymodExtended.onSettingChanged.add(change -> applySetting(change.modId, change.key, change.value));
```

## API

### `PolymodExtended`

| Member | Description |
| --- | --- |
| `init(?config)` | Mounts archives, scans mods, syncs the mod list and loads every enabled mod |
| `scan()` | Rescans the mod folder (including new archives) without loading |
| `reload()` | Rescans and reloads the enabled mods |
| `setModEnabled(id, enabled, reloadNow)` | Enables or disables a mod |
| `moveMod(id, index, reloadNow)` | Moves a mod in the list |
| `setModList(list, reloadNow)` | Replaces the whole mod list |
| `getSetting(modId, key)` / `setSetting(modId, key, value)` / `resetSettings(modId, ?key)` | Mod settings |
| `getMod(id)` / `getModOptions(id)` / `getModData(id)` | Metadata, parsed options and custom data |
| `getModsByTag(tag)` / `getVisibleMods()` | Filtering helpers |
| `isModLoaded(id)` / `getSkipReason(id)` | Load state and why a mod was skipped |
| `save()` / `saveModList()` / `saveSettings()` | Manual saving |
| `unloadAll()` | Unloads every mod |
| `availableMods` / `loadedMods` / `skippedMods` | Current state |
| `fileSystem` | The file system in use (`ArchiveFileSystem` on native targets, `VirtualFileSystem` on the web) |
| `onModsScanned` / `onModsLoaded` / `onModListChanged` / `onSettingChanged` / `onError` | Signals |
| `log` | `ErrorLog` with every error, warning and info message |

### `ExtendedConfig`

Accepts the usual Polymod options (`framework`, `frameworkParams`, `customBackend`, `customFilesystem`, `apiVersionRule`, `parseRules`, `ignoredFiles`, `extensionMap`, `assetPrefix`, `useScriptedClasses`, `loadScriptsAsync`, `skipDependencyChecks`, `skipDependencyErrors`) plus:

| Field | Default | Description |
| --- | --- | --- |
| `modRoot` | `"./mods"` | Folder that contains the mods |
| `modRoots` | none | Extra folders whose mods are loaded too |
| `modList` | loaded from `modListFile` | Saved order and enabled state |
| `settings` | loaded from `settingsFile` | Saved mod settings |
| `modListFile` / `settingsFile` | none | JSON files used for loading and saving (`localStorage` keys on the web) |
| `autoSave` | `true` | Save automatically after every change |
| `enableNewMods` | `true` | Whether mods found for the first time start enabled |
| `archives` | `true` | Load `.zip` and `.rar` mods |
| `gameVersion` | none | Version checked against each mod's `gameVersion` rule |
| `structure` | none | `ModStructure` used for validation, templates and organizing |
| `validateStructure` | `true` | Validate mods against `structure` on every scan |
| `gameLayout` | none | Your game's folder layout, enables mapping for mods made for other engines |
| `detectLayouts` | `true` | Detect each mod's layout from its files |
| `layoutMappings` | none | Custom mappings per mod layout, replacing the built-in ones |
| `allowAppSettings` | `false` | Let mods change the default app settings |
| `scripts` | `false` | Load HScript files from each mod's `scripts` folder |
| `skipDependencyErrors` | `true` | Skip only the mods with missing dependencies |
| `maxLogEntries` | `256` | Size limit of the error log, `0` for unlimited |

## Running the tests

```bash
cd test
haxe test.hxml

cd web
npm install
haxe web.hxml
npm test
```

The archive fixtures in `test/mods` are generated by `test/fixtures/make_archives.py`.

## License

[MIT](LICENSE)
