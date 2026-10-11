package polymod.extended;

import polymod.Polymod;
import polymod.Polymod.ModMetadata;
import polymod.Polymod.PolymodError;
import polymod.Polymod.PolymodParams;
import polymod.extended.util.Signal;

class PolymodExtended
{
	public static inline final VERSION:String = "0.1.0";

	public static inline final DEFAULT_MOD_ROOT:String = "./mods";

	public static final onModsScanned:Signal<Array<ModMetadata>> = new Signal();

	public static final onModsLoaded:Signal<Array<ModMetadata>> = new Signal();

	public static final onError:Signal<PolymodError> = new Signal();

	public static final log:ErrorLog = new ErrorLog();

	public static var config(default, null):ExtendedConfig = {};

	public static var modList(default, null):ModList = new ModList();

	public static var availableMods(default, null):Array<ModMetadata> = [];

	public static var loadedMods(default, null):Array<ModMetadata> = [];

	public static var initialized(default, null):Bool = false;

	public static function init(?config:ExtendedConfig):Array<ModMetadata>
	{
		PolymodExtended.config = config != null ? config : {};

		if (PolymodExtended.config.modRoot == null)
			PolymodExtended.config.modRoot = DEFAULT_MOD_ROOT;

		if (PolymodExtended.config.modList != null)
			modList = PolymodExtended.config.modList;

		if (PolymodExtended.config.maxLogEntries != null)
			log.maxEntries = PolymodExtended.config.maxLogEntries;

		scan();

		loadedMods = Polymod.init(buildParams(modList.getEnabledIds()));

		if (loadedMods == null)
			loadedMods = [];

		initialized = true;
		onModsLoaded.dispatch(loadedMods);
		return loadedMods;
	}

	public static function scan():Array<ModMetadata>
	{
		availableMods = Polymod.scan({
			modRoot: config.modRoot,
			apiVersionRule: config.apiVersionRule,
			errorCallback: handleError
		});

		if (availableMods == null)
			availableMods = [];

		modList.sync([for (mod in availableMods) mod.id], config.enableNewMods != false);
		onModsScanned.dispatch(availableMods);
		return availableMods;
	}

	public static function reload():Array<ModMetadata>
	{
		if (!initialized)
			return init(config);

		scan();

		loadedMods = Polymod.loadOnlyMods(modList.getEnabledIds());

		if (loadedMods == null)
			loadedMods = [];

		onModsLoaded.dispatch(loadedMods);
		return loadedMods;
	}

	public static function setModEnabled(id:String, enabled:Bool, reloadNow:Bool = false):Void
	{
		modList.setEnabled(id, enabled);

		if (reloadNow)
			reload();
	}

	public static function setModList(list:ModList, reloadNow:Bool = false):Void
	{
		modList = list != null ? list : new ModList();

		if (reloadNow)
			reload();
	}

	public static function getMod(id:String):Null<ModMetadata>
	{
		for (mod in availableMods)
			if (mod.id == id)
				return mod;

		return null;
	}

	public static function isModLoaded(id:String):Bool
	{
		for (mod in loadedMods)
			if (mod.id == id)
				return true;

		return false;
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

	static function buildParams(modIds:Array<String>):PolymodParams
	{
		return {
			modRoot: config.modRoot,
			modIds: modIds,
			framework: config.framework,
			frameworkParams: config.frameworkParams,
			customBackend: config.customBackend,
			customFilesystem: config.customFilesystem,
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

	static function handleError(error:PolymodError):Void
	{
		log.add(error);
		onError.dispatch(error);
	}
}
