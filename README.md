# polymod-extended

An expanded modding framework for Haxe games, built on top of [Polymod](https://github.com/larsiusprime/polymod).

polymod-extended keeps Polymod as the engine underneath and adds a management layer on top of it:

- Mods packed as `.zip` or `.rar` files, loaded straight from the archive
- An ordered mod list you can save and restore, with enabling, disabling and reordering at runtime
- Extra mod options in `_polymod_meta.json`: priority, load order rules, incompatibilities, platform and game version filters, tags, custom data and user settings
- Automatic saving of the mod list and mod settings
- A web API for HTML5 builds: mods from URLs, uploads, drag and drop, and mods kept in the browser
- A desktop API: install, uninstall, export and create mods, open the mods folder and reload when files change
- One-call reloading, a central error log and signals your game can listen to

## Installation

polymod-extended targets Polymod 2.0, which is currently only available from git.

```bash
haxelib git polymod https://github.com/larsiusprime/polymod
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
| `loadUrl(url, ?dirName, install)` | Downloads a `.zip` or `.rar` and loads it. With `install: true` it is also kept in the browser. |
| `loadIndex(url, install)` | Loads every mod listed in a JSON index, see below |
| `openFilePicker(multiple)` | Opens the browser file picker and installs the chosen archives. Call it from a click or key press. |
| `enableDropZone(?element)` | Installs archives dropped on the page (or on `element`). Returns a function that turns it off. |
| `installBytes(bytes, name)` / `installBlob(file)` | Installs an archive you already have |
| `restoreInstalled()` | Loads every mod the player installed before. Call it once at startup. |
| `uninstall(dirName)` / `clearInstalled()` / `listInstalled()` | Manages installed mods |
| `onInstalled` / `onUninstalled` / `onLoadFailed` | Signals |

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
| `modList` | loaded from `modListFile` | Saved order and enabled state |
| `settings` | loaded from `settingsFile` | Saved mod settings |
| `modListFile` / `settingsFile` | none | JSON files used for loading and saving (`localStorage` keys on the web) |
| `autoSave` | `true` | Save automatically after every change |
| `enableNewMods` | `true` | Whether mods found for the first time start enabled |
| `archives` | `true` | Load `.zip` and `.rar` mods |
| `gameVersion` | none | Version checked against each mod's `gameVersion` rule |
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
