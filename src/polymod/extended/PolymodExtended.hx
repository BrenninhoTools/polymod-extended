package polymod.extended;

import polymod.Polymod;
import polymod.Polymod.ModMetadata;
import polymod.Polymod.PolymodError;
import polymod.Polymod.PolymodErrorCode;
import polymod.Polymod.PolymodParams;
import polymod.PolymodConfig;
import polymod.extended.structure.FolderLayouts;
import polymod.extended.structure.FolderMapper;
import polymod.extended.structure.ModStructure;
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
	public static inline final VERSION:String = "0.6.0";

	public static inline final DEFAULT_MOD_ROOT:String = "./mods";

	public static inline final MOD_SKIPPED:PolymodErrorCode = "mod_skipped";

	public static inline final MOD_OPTIONS_INVALID:PolymodErrorCode = "mod_options_invalid";

	public static inline final MOD_ORDER_WARNING:PolymodErrorCode = "mod_order_warning";

	public static inline final SAVE_FAILED:PolymodErrorCode = "save_failed";

	public static inline final MOD_DUPLICATE_ID:PolymodErrorCode = "mod_duplicate_id";

	public static inline final CATEGORY_INVALID:PolymodErrorCode = "category_invalid";

	public static inline final MOD_STRUCTURE:PolymodErrorCode = "mod_structure";

	public static inline final MOD_LAYOUT:PolymodErrorCode = "mod_layout";

	public static inline final HOOK_MODS_LOADED:String = "modsLoaded";

	public static var maxStructureWarnings:Int = 10;

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

	public static var categories(default, null):Array<ModCategory> = [];

	static var structureIssues:Map<String, Array<StructureIssue>> = [];

	static var modLayouts:Map<String, String> = [];

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

		if (current.allowAppSettings == true)
			polymod.extended.app.ModAppSettings.allowDefaults();

		if (current.useScriptedClasses == true)
		{
			Polymod.addDefaultImport(polymod.extended.hooks.ModHooks, "ModHooks");
			Polymod.addDefaultImport(polymod.extended.hooks.ModHooks.ModEvent, "ModEvent");
		}

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

		var mapper = getMapper();

		if (mapper != null)
			mapper.clear();

		var mods = Polymod.scan({
			modRoot: config.modRoot,
			apiVersionRule: config.apiVersionRule,
			errorCallback: handleError,
			fileSystem: fileSystem
		});

		var found = mods != null ? mods : [];
		found.sort((a, b) -> a.id < b.id ? -1 : (a.id > b.id ? 1 : 0));

		var folderCategories = scanCategories(found);
		availableMods = [];

		for (mod in found)
		{
			if (getMod(mod.id) != null)
			{
				Polymod.warning(MOD_DUPLICATE_ID, 'Mod id "${mod.id}" is used by more than one folder, ignoring "${mod.dirName}"', SCAN);
				continue;
			}

			availableMods.push(mod);
		}

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

		categories = buildCategories(folderCategories);
		applyLayouts();
		validateStructures();
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

	public static function getCategory(id:String):Null<ModCategory>
	{
		for (category in categories)
			if (category.id == id)
				return category;

		return null;
	}

	public static function getModCategory(modId:String):Null<ModCategory>
	{
		for (category in categories)
			if (category.mods.contains(modId))
				return category;

		return null;
	}

	public static function getModsInCategory(categoryId:String):Array<ModMetadata>
	{
		var category = getCategory(categoryId);
		return category != null ? [for (id in category.mods) getMod(id)].filter(mod -> mod != null) : [];
	}

	public static function getUncategorizedMods():Array<ModMetadata>
	{
		return availableMods.filter(mod -> getModCategory(mod.id) == null);
	}

	public static function getStructureIssues(id:String):Array<StructureIssue>
	{
		var issues = structureIssues.get(id);
		return issues != null ? issues.copy() : [];
	}

	public static function validateMod(id:String, ?structure:ModStructure):Array<StructureIssue>
	{
		var mod = getMod(id);
		var rules = structure != null ? structure : config.structure;

		if (mod == null || rules == null)
			return [];

		return rules.validate(listModFiles(mod, true));
	}

	public static function getModLayout(id:String):Null<String>
	{
		return modLayouts.get(id);
	}

	public static function getFolderMappings(id:String):Array<FolderMapping>
	{
		var mod = getMod(id);
		var mapper = getMapper();
		return mod != null && mapper != null ? mapper.getMappings(modPath(mod)) : [];
	}

	public static function listModFiles(mod:ModMetadata, raw:Bool = false):Array<String>
	{
		var path = modPath(mod);
		var mapper = getMapper();
		var saved:Array<FolderMapping> = null;

		if (raw && mapper != null)
		{
			saved = mapper.getMappings(path);
			mapper.remove(path);
		}

		var files = fileSystem.exists(path) ? fileSystem.readDirectoryRecursive(path) : [];

		if (saved != null && saved.length > 0)
			mapper.set(path, saved);

		return [for (file in files) StringTools.replace(file, "\\", "/")];
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
		polymod.extended.hooks.ModHooks.clearMods();
		polymod.extended.app.ModAppSettings.refresh(loadedMods);

		if (config.scripts == true)
			polymod.extended.scripting.ModScripts.destroyAll();

		onModsLoaded.dispatch(loadedMods);
		polymod.extended.hooks.ModHooks.call(HOOK_MODS_LOADED, loadedMods, false);
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

		polymod.extended.hooks.ModHooks.clearMods();

		var dirs = [for (id in resolved.order) getModDir(id)];
		var result = first ? Polymod.init(buildParams(dirs)) : Polymod.loadOnlyModsByDir(dirs);
		loadedMods = result != null ? result : [];
		polymod.extended.app.ModAppSettings.refresh(loadedMods);

		if (config.scripts == true)
			polymod.extended.scripting.ModScripts.reload();

		onModsLoaded.dispatch(loadedMods);
		polymod.extended.hooks.ModHooks.call(HOOK_MODS_LOADED, loadedMods, false);
	}

	static function applyLayouts():Void
	{
		modLayouts = [];
		var mapper = getMapper();

		for (mod in availableMods)
		{
			var options = getModOptions(mod.id);
			var layout = options.layout != null ? FolderLayouts.normalizeName(options.layout) : null;

			if ((layout == null || layout == "auto") && config.detectLayouts != false && config.gameLayout != null)
				layout = FolderLayouts.detect(listModFiles(mod, true));

			if (layout != null && layout != "auto")
				modLayouts.set(mod.id, layout);

			var mappings:Array<FolderMapping> = [];

			if (layout != null && config.gameLayout != null)
			{
				var custom = config.layoutMappings != null ? config.layoutMappings.get(layout) : null;
				mappings = custom != null ? custom.copy() : FolderLayouts.mappings(layout, config.gameLayout);
			}

			for (folder in options.folders)
				mappings.push({from: folder.from, to: folder.to});

			if (mappings.length == 0)
				continue;

			if (mapper == null)
			{
				Polymod.warning(MOD_LAYOUT, 'Mod "${mod.id}" uses folder mappings, but the current file system does not support them', SCAN);
				continue;
			}

			for (error in mapper.set(modPath(mod), mappings))
				Polymod.warning(MOD_LAYOUT, 'Mod "${mod.id}": $error', SCAN);
		}
	}

	static function validateStructures():Void
	{
		structureIssues = [];

		if (config.structure == null || config.validateStructure == false)
			return;

		for (mod in availableMods)
		{
			var issues = config.structure.validate(listModFiles(mod, true));

			if (issues.length == 0)
				continue;

			structureIssues.set(mod.id, issues);
			var shown = 0;

			for (issue in issues)
			{
				if (shown >= maxStructureWarnings)
				{
					Polymod.warning(MOD_STRUCTURE, 'Mod "${mod.id}": ${issues.length - shown} more structure issue(s)', SCAN);
					break;
				}

				Polymod.warning(MOD_STRUCTURE, 'Mod "${mod.id}": ${issue.message}' + (issue.suggestion != null ? ', move it to "${issue.suggestion}"' : ""), SCAN);
				shown++;
			}
		}
	}

	static function getMapper():Null<FolderMapper>
	{
		if (fileSystem != null && Std.isOfType(fileSystem, IFolderMapping))
			return (cast fileSystem : IFolderMapping).mapper;

		return null;
	}

	static function modPath(mod:ModMetadata):String
	{
		return mod.modPath != null ? mod.modPath : Util.pathJoin(config.modRoot, mod.dirName != null ? mod.dirName : mod.id);
	}

	static function getModDir(id:String):String
	{
		var mod = getMod(id);
		return mod != null && mod.dirName != null ? mod.dirName : id;
	}

	static function scanCategories(found:Array<ModMetadata>):Array<ModCategory>
	{
		var result:Array<ModCategory> = [];
		var root = config.modRoot;
		var metaFile = PolymodConfig.modMetadataFile;

		if (!fileSystem.exists(root) || !fileSystem.isDirectory(root))
			return result;

		var names = fileSystem.readDirectory(root);
		names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		for (name in names)
		{
			var path = Util.pathJoin(root, name);

			if (StringTools.startsWith(name, ".") || !fileSystem.isDirectory(path) || fileSystem.exists(Util.pathJoin(path, metaFile)))
				continue;

			var category = new ModCategory(name, true);
			var categoryFile = Util.pathJoin(path, ModCategory.metadataFile);
			var hasFile = fileSystem.exists(categoryFile);

			if (hasFile)
			{
				var errors:Array<String> = [];
				category.apply(fileSystem.getFileContent(categoryFile), errors);

				for (error in errors)
					Polymod.warning(CATEGORY_INVALID, error, SCAN);
			}

			var children = fileSystem.readDirectory(path);
			children.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			for (child in children)
			{
				var childPath = Util.pathJoin(path, child);

				if (!fileSystem.isDirectory(childPath) || !fileSystem.exists(Util.pathJoin(childPath, metaFile)))
					continue;

				var meta = fileSystem.getMetadataByDir(name + "/" + child, SCAN);

				if (meta == null)
					continue;

				var rule = config.apiVersionRule != null ? config.apiVersionRule : polymod.util.VersionUtil.DEFAULT_VERSION_RULE;

				if (!polymod.util.VersionUtil.match(meta.apiVersion, rule))
				{
					Polymod.warning(MOD_API_VERSION_MISMATCH, 'Mod "${meta.id}" is not compatible with API version "${rule.toString()}"', SCAN);
					continue;
				}

				found.push(meta);
				category.mods.push(meta.dirName != null ? meta.dirName : name + "/" + child);
			}

			if (category.mods.length > 0 || hasFile)
				result.push(category);
		}

		return result;
	}

	static function buildCategories(folderCategories:Array<ModCategory>):Array<ModCategory>
	{
		var result:Array<ModCategory> = [];

		for (category in folderCategories)
		{
			var dirs = category.mods.copy();
			category.mods.resize(0);

			for (mod in availableMods)
				if (dirs.contains(mod.dirName) && !category.mods.contains(mod.id))
					category.mods.push(mod.id);

			result.push(category);
		}

		for (mod in availableMods)
		{
			var declared = getModOptions(mod.id).category;

			if (declared == null || result.filter(category -> category.mods.contains(mod.id)).length > 0)
				continue;

			var existing:Null<ModCategory> = null;

			for (category in result)
				if (category.id == declared || category.title.toLowerCase() == declared.toLowerCase())
					existing = category;

			if (existing == null)
			{
				existing = new ModCategory(declared, false);
				result.push(existing);
			}

			existing.mods.push(mod.id);
		}

		ModCategory.sort(result);
		return result;
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
			return new polymod.extended.fs.ArchiveFileSystem({modRoot: config.modRoot}, config.modRoots);

		return PolymodFileSystem.makeFileSystem(null, {modRoot: config.modRoot});
		#else
		return new polymod.extended.fs.VirtualFileSystem({modRoot: config.modRoot});
		#end
	}

	static function buildParams(dirs:Array<String>):PolymodParams
	{
		return {
			modRoot: config.modRoot,
			modIds: [],
			dirs: dirs,
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
