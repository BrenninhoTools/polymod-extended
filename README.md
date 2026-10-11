# polymod-extended

An expanded modding framework for Haxe games, built on top of [Polymod](https://github.com/larsiusprime/polymod).

polymod-extended keeps Polymod as the engine underneath and adds a management layer on top of it: an ordered mod list you can save and restore, enabling and disabling mods at runtime, one-call reloading, a central error log and signals your game can listen to.

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
import polymod.extended.ModList;
import polymod.extended.PolymodExtended;

class ModHandler
{
	public static function init():Void
	{
		PolymodExtended.onError.add(error -> showError(error.message));

		PolymodExtended.init({
			modRoot: "mods",
			framework: Framework.FLIXEL,
			modList: ModList.fromJson(loadSavedModList()),
			enableNewMods: true
		});
	}

	public static function toggle(id:String):Void
	{
		PolymodExtended.setModEnabled(id, !PolymodExtended.modList.isEnabled(id), true);
		saveModList(PolymodExtended.modList.toJson());
	}
}
```

`showError`, `loadSavedModList` and `saveModList` are yours to implement (`FlxSave`, a file, `SharedObject`, etc). polymod-extended only produces and reads the JSON.

## API

### `PolymodExtended`

| Member | Description |
| --- | --- |
| `init(?config)` | Scans the mod folder, syncs the mod list and loads every enabled mod |
| `scan()` | Rescans the mod folder and syncs the mod list without loading |
| `reload()` | Rescans and reloads only the enabled mods |
| `setModEnabled(id, enabled, reloadNow)` | Enables or disables a mod, optionally reloading right away |
| `setModList(list, reloadNow)` | Replaces the whole mod list |
| `unloadAll()` | Unloads every mod |
| `getMod(id)` | Metadata of an available mod |
| `isModLoaded(id)` | Whether a mod is currently loaded |
| `availableMods` / `loadedMods` | Last scan result and currently loaded mods |
| `onModsScanned` / `onModsLoaded` / `onError` | Signals |
| `log` | `ErrorLog` with every error, warning and info message Polymod reported |

### `ExtendedConfig`

Accepts the usual Polymod options (`framework`, `frameworkParams`, `customBackend`, `customFilesystem`, `apiVersionRule`, `parseRules`, `ignoredFiles`, `extensionMap`, `assetPrefix`, `useScriptedClasses`, `loadScriptsAsync`, `skipDependencyChecks`, `skipDependencyErrors`) plus:

| Field | Default | Description |
| --- | --- | --- |
| `modRoot` | `"./mods"` | Folder that contains the mods |
| `modList` | empty | Saved order and enabled state |
| `enableNewMods` | `true` | Whether mods found for the first time start enabled |
| `maxLogEntries` | `256` | Size limit of the error log, `0` for unlimited |

### `ModList`

Ordered list of `{id, enabled}` entries with `add`, `remove`, `setEnabled`, `toggle`, `move`, `sync`, `getEnabledIds`, `toJson` and `fromJson`. Mods that depend on each other are always loaded in dependency order by Polymod.

## Mod metadata

Always set an explicit `id` in `_polymod_meta.json`. Dependencies are matched by id.

```json
{
  "id": "my_mod",
  "title": "My Mod",
  "api_version": "0.1.0",
  "mod_version": "1.0.0",
  "dependencies": {
    "other_mod": "1.0.0"
  }
}
```

## Running the tests

```bash
cd test
haxe test.hxml
```

## License

[MIT](LICENSE)
