package polymod.extended;

import polymod.Polymod;
import polymod.Polymod.ModMetadata;
import polymod.Polymod.PolymodError;
import polymod.Polymod.PolymodErrorCode;
import polymod.Polymod.PolymodParams;
import polymod.PolymodConfig;
import polymod.extended.util.Signal;
import polymod.fs.PolymodFileSystem;
import polymod.util.Util;

typedef ModSettingChange =
{
	modId:String,
	key:String,
	value:Dynamic
}

class PolymodExtended
{
	public static inline final VERSION:String = "0.3.0";

	public static inline final DEFAULT_MOD_ROOT:String = "./mods";

	public static inline final MOD_SKIPPED:PolymodErrorCode = "mod_skipped";

	public static inline final MOD_OPTIONS_INVALID:PolymodErrorCode = "mod_options_invalid";

	public static inline final MOD_ORDER_WARNING:PolymodErrorCode = "mod_order_warning";

	public static inline final SAVE_FAILED:PolymodErrorCode = "save_failed";

	public static final onModsScanned:Signal<Array<ModMetadata>> = new Signal();

	public static final onModsLoaded:Signal<Array<ModMetadata>> = new Signal();

	public static final onModListChanged:Signal<ModList> = new Signal();

	public static final onSettingChanged:Signal<ModSettingChange> = new Signal();

	public static final onError:Signal<PolymodError> = new Signal();

	public static final log:ErrorLog = new ErrorLog();

	public static var config(default, null):ExtendedConfig = {};

	public static var modList(default, null):ModList = new ModList();

	public static var settings(default, null):ModSettings = new ModSettings();

	public static var fileSystem(default, null):IFileSystem;

	public static var availableMods(default, null):Array<ModMetadata> = [];

	public static var loadedMods(default, null):Array<ModMetadata> = [];

	public static var skippedMods(default, null):Map<String, String> = [];

	public static var initialized(default, null):Bool = false;

	static var options:Map<String, ModOptions> = [];

	public static function init(?config:ExtendedConfig):Array<ModMetadata>
	{
		PolymodExtended.config = config != null ? config : {};
		var current = PolymodExtended.config;

		if (current.modRoot == null)
			current.modRoot = DEFAULT_MOD_ROOT;

		if (current.skipDependencyErrors == null)
			current.skipDependencyErrors = true;

		if (current.maxLogEntries != null)
			log.maxEntries = current.maxLogEntries;

		Polymod.onError = handleError;

		modList = current.modList != null ? current.modList : loadModListFile();
		settings = current.settings != null ? current.settings : loadSettingsFile();
		fileSystem = createFileSystem();

		scan();
		load(true);
		initialized = true;
		return loadedMods;
	}

	public static function scan():Array<ModMetadata>
	{
		if (fileSystem == null)
			fileSystem = createFileSystem();

		#if sys
		if (initialized && Std.isOfType(fileSystem, polymod.extended.fs.ArchiveFileSystem))
			(cast fileSystem : polymod.extended.fs.ArchiveFileSystem).refresh();
		#end

		var mods = Polymod.scan({
			modRoot: config.modRoot,
			apiVersionRule: config.apiVersionRule,
			errorCallback: handleError,
			fileSystem: fileSystem
		});

		availableMods = mods != null ? mods : [];
		availableMods.sort((a, b) -> a.id < b.id ? -1 : (a.id > b.id ? 1 : 0));
		options = [];

		for (mod in availableMods)
		{
			var parsed = readOptions(mod);
			options.set(mod.id, parsed);
			settings.define(mod.id, parsed.settings);

			for (error in parsed.errors)
				Polymod.warning(MOD_OPTIONS_INVALID, 'Mod "${mod.id}": $error', SCAN);
		}

		modList.sync([for (mod in availableMods) mod.id], config.enableNewMods != false, id -> getModOptions(id).enabledByDefault);
		onModsScanned.dispatch(availableMods);
		return availableMods;
	}

	public static function reload():Array<ModMetadata>
	{
		if (!initialized)
			return init(config);

		scan();
		load(false);
		return loadedMods;
	}

	public static function setModEnabled(id:String, enabled:Bool, reloadNow:Bool = false):Void
	{
		modList.setEnabled(id, enabled);
		modListChanged();

		if (reloadNow)
			reload();
	}

	public static function moveMod(id:String, index:Int, reloadNow:Bool = false):Void
	{
		if (modList.move(id, index))
			modListChanged();

		if (reloadNow)
			reload();
	}

	public static function setModList(list:ModList, reloadNow:Bool = false):Void
	{
		modList = list != null ? list : new ModList();
		modListChanged();

		if (reloadNow)
			reload();
	}

	public static function getSetting(modId:String, key:String):Dynamic
	{
		return settings.get(modId, key);
	}

	public static function setSetting(modId:String, key:String, value:Dynamic):Bool
	{
		if (!settings.set(modId, key, value))
			return false;

		if (shouldAutoSave())
			saveSettings();

		onSettingChanged.dispatch({modId: modId, key: key, value: settings.get(modId, key)});
		return true;
	}

	public static function resetSettings(modId:String, ?key:String):Void
	{
		settings.reset(modId, key);

		if (shouldAutoSave())
			saveSettings();

		for (setting in settings.getDefinitions(modId))
			if (key == null || setting.id == key)
				onSettingChanged.dispatch({modId: modId, key: setting.id, value: settings.get(modId, setting.id)});
	}

	public static function getMod(id:String):Null<ModMetadata>
	{
		for (mod in availableMods)
			if (mod.id == id)
				return mod;

		return null;
	}

	public static function getModOptions(id:String):ModOptions
	{
		var result = options.get(id);
		return result != null ? result : new ModOptions();
	}

	public static function getModData(id:String):Dynamic
	{
		return getModOptions(id).data;
	}

	public static function getModsByTag(tag:String):Array<ModMetadata>
	{
		return availableMods.filter(mod -> getModOptions(mod.id).hasTag(tag));
	}

	public static function getVisibleMods():Array<ModMetadata>
	{
		return availableMods.filter(mod -> !getModOptions(mod.id).hidden);
	}

	public static function isModLoaded(id:String):Bool
	{
		for (mod in loadedMods)
			if (mod.id == id)
				return true;

		return false;
	}

	public static function getSkipReason(id:String):Null<String>
	{
		return skippedMods.get(id);
	}

	public static function getLoadedModIds():Array<String>
	{
		return [for (mod in loadedMods) mod.id];
	}

	public static function unloadAll():Void
	{
		if (!initialized)
			return;

		Polymod.unloadAllMods();
		loadedMods = [];
		onModsLoaded.dispatch(loadedMods);
	}

	public static function save():Void
	{
		saveModList();
		saveSettings();
	}

	public static function saveModList():Bool
	{
		return writeFile(config.modListFile, modList.toJson(true));
	}

	public static function saveSettings():Bool
	{
		return writeFile(config.settingsFile, settings.toJson(true));
	}

	static function load(first:Bool):Void
	{
		var resolved = ModResolver.resolve(modList.getEnabledIds(), getMod, getModOptions, config.gameVersion);
		skippedMods = resolved.skipped;

		for (id => reason in resolved.skipped)
			Polymod.warning(MOD_SKIPPED, 'Skipping mod "$id": $reason', INIT);

		for (warning in resolved.warnings)
			Polymod.warning(MOD_ORDER_WARNING, warning, INIT);

		var result = first ? Polymod.init(buildParams(resolved.order)) : Polymod.loadOnlyMods(resolved.order);
		loadedMods = result != null ? result : [];
		onModsLoaded.dispatch(loadedMods);
	}

	static function readOptions(mod:ModMetadata):ModOptions
	{
		var path = Util.pathJoin(mod.modPath != null ? mod.modPath : Util.pathJoin(config.modRoot, mod.dirName), PolymodConfig.modMetadataFile);

		try
		{
			return ModOptions.fromJsonString(fileSystem.exists(path) ? fileSystem.getFileContent(path) : null);
		}
		catch (e:Dynamic)
		{
			var result = new ModOptions();
			result.errors.push('could not read metadata: ${Std.string(e)}');
			return result;
		}
	}

	static function createFileSystem():IFileSystem
	{
		if (config.customFilesystem != null)
			return PolymodFileSystem.makeFileSystem(config.customFilesystem, {modRoot: config.modRoot});

		#if sys
		if (config.archives != false)
			return new polymod.extended.fs.ArchiveFileSystem({modRoot: config.modRoot});

		return PolymodFileSystem.makeFileSystem(null, {modRoot: config.modRoot});
		#else
		return new polymod.extended.fs.VirtualFileSystem({modRoot: config.modRoot});
		#end
	}

	static function buildParams(modIds:Array<String>):PolymodParams
	{
		return {
			modRoot: config.modRoot,
			modIds: modIds,
			framework: config.framework,
			frameworkParams: config.frameworkParams,
			customBackend: config.customBackend,
			customFilesystem: fileSystem,
			apiVersionRule: config.apiVersionRule,
			errorCallback: handleError,
			parseRules: config.parseRules,
			ignoredFiles: config.ignoredFiles,
			extensionMap: config.extensionMap,
			assetPrefix: config.assetPrefix,
			useScriptedClasses: config.useScriptedClasses,
			loadScriptsAsync: config.loadScriptsAsync,
			skipDependencyChecks: config.skipDependencyChecks,
			skipDependencyErrors: config.skipDependencyErrors
		};
	}

	static function modListChanged():Void
	{
		if (shouldAutoSave())
			saveModList();

		onModListChanged.dispatch(modList);
	}

	static function shouldAutoSave():Bool
	{
		return config.autoSave != false;
	}

	static function loadModListFile():ModList
	{
		var text = readFile(config.modListFile);
		return text != null ? ModList.fromJson(text) : new ModList();
	}

	static function loadSettingsFile():ModSettings
	{
		var text = readFile(config.settingsFile);
		return text != null ? ModSettings.fromJson(text) : new ModSettings();
	}

	static function readFile(path:String):Null<String>
	{
		return polymod.extended.util.Storage.read(path);
	}

	static function writeFile(path:String, content:String):Bool
	{
		if (path == null)
			return false;

		if (polymod.extended.util.Storage.write(path, content))
			return true;

		Polymod.error(SAVE_FAILED, 'Could not save "$path"');
		return false;
	}

	static function handleError(error:PolymodError):Void
	{
		log.add(error);
		onError.dispatch(error);
	}
}
