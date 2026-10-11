package;

import haxe.io.Bytes;
import polymod.Polymod.Framework;
import polymod.Polymod.ModMetadata;
import polymod.extended.ModList;
import polymod.extended.ModOptions;
import polymod.extended.ModResolver;
import polymod.extended.ModSetting;
import polymod.extended.ModSettings;
import polymod.extended.PolymodExtended;
import polymod.extended.archive.Archive;
import polymod.extended.archive.ArchiveFormats;
import polymod.extended.archive.ZipArchive;
import polymod.extended.fs.ArchiveFileSystem;
import polymod.extended.app.ModAppSettings;
import polymod.extended.images.ImageAtlas;
import polymod.extended.images.ImageInfo;
import polymod.extended.images.ModImages;
import polymod.extended.scripting.ModScript;
import polymod.extended.scripting.ModScripts;
import polymod.extended.scripting.ScriptSandbox;
import polymod.extended.hooks.ModHooks;
import polymod.extended.desktop.DesktopMods;
import polymod.extended.desktop.ModOrganizer;
import polymod.extended.desktop.RemoteMods;
import polymod.extended.sources.DropboxSource;
import polymod.extended.sources.GameBananaSource;
import polymod.extended.sources.GoogleDriveSource;
import polymod.extended.sources.HttpClient;
import polymod.extended.sources.MediaFireSource;
import polymod.extended.sources.ModSources;
import polymod.extended.sources.ModSources.ResolveOptions;
import polymod.extended.sources.ModSources.ResolvedMod;
import polymod.extended.sources.HttpClient.MockHttpClient;
import polymod.extended.desktop.RemoteMods.RemoteProgress;
import polymod.extended.desktop.RemoteMods.RemoteInstallResult;
import polymod.extended.structure.FolderLayouts;
import polymod.extended.structure.FolderMapper;
import polymod.extended.structure.ModStructure;
import polymod.extended.structure.StructurePresets;
import polymod.extended.util.ModPaths;
import polymod.extended.util.Platform;
import polymod.extended.util.Signal;

class Main
{
	static inline final OUT:String = "out";

	static var passed:Int = 0;
	static var failed:Int = 0;

	static function main():Void
	{
		clearOutput();

		section("Signal");
		testSignal();
		section("ModList");
		testModList();
		section("Archives");
		testArchives();
		section("ModOptions");
		testModOptions();
		section("ModSettings");
		testModSettings();
		section("ModResolver");
		testResolver();
		section("PolymodExtended");
		testPolymodExtended();
		section("DesktopMods");
		testDesktopMods();
		section("Folder organization");
		testOrganization();
		section("App settings");
		testAppSettings();
		section("Mod hooks");
		testHooks();
		section("Mod roots");
		testRoots();
		section("Mod images");
		testImages();
		section("Mod scripts");
		testScripts();
		section("Mod sources");
		testSources();
		section("Remote installs");
		testRemoteMods();

		Sys.println('\nPassed: $passed, Failed: $failed');
		Sys.exit(failed > 0 ? 1 : 0);
	}

	static function testSignal():Void
	{
		var signal = new Signal<Int>();
		var total = 0;
		var listener = (value:Int) -> total += value;

		signal.add(listener);
		signal.add(listener);
		signal.addOnce(value -> total += value * 10);
		signal.dispatch(1);
		signal.dispatch(1);
		check("dispatches regular and once listeners", total == 12);

		signal.remove(listener);
		signal.dispatch(5);
		check("removes listeners", total == 12 && signal.count == 0);
	}

	static function testModList():Void
	{
		var list = new ModList();
		list.add("a");
		list.add("b", false);
		list.add("c");
		list.add("a");
		check("ignores duplicates", list.length == 3);
		check("returns enabled ids in order", list.getEnabledIds().join(",") == "a,c");

		list.move("c", 0);
		check("moves entries", list.getEnabledIds().join(",") == "c,a");

		list.toggle("b");
		check("toggles entries", list.isEnabled("b"));

		var restored = ModList.fromJson(list.toJson());
		check("survives a JSON round trip", restored.toJson() == list.toJson());
		check("handles invalid JSON", ModList.fromJson("{oops").length == 0);

		list.sync(["a", "d", "e"], true, id -> id != "e");
		check("sync removes missing mods", !list.has("b") && !list.has("c"));
		check("sync applies per-mod defaults", list.isEnabled("d") && !list.isEnabled("e"));
		check("sync keeps existing state", list.isEnabled("a"));
	}

	static function testArchives():Void
	{
		var zip = ArchiveFormats.openFile("mods/zip_mod.zip");
		check("opens zip archives", zip.format == "zip");
		check("reads deflated zip entries", text(zip.read("zip_mod_folder/data/info.json")).indexOf("zip") != -1);
		check("inflates large zip entries", zip.read("zip_mod_folder/data/big.txt").length == 68000);
		check("zip lookups are case-insensitive", zip.has("ZIP_MOD_FOLDER/DATA/INFO.JSON"));
		zip.close();

		var rar5 = ArchiveFormats.openFile("mods/rar5_mod.rar");
		check("opens RAR5 archives", rar5.format == "rar" && rar5.getUnsupportedEntries().length == 0);
		check("reads stored RAR5 entries", text(rar5.read("data/info.json")).indexOf("rar5") != -1);
		check("reads unicode RAR5 names", text(rar5.read("data/ação.txt")) == "unicode name");
		check("marks RAR5 directories", rar5.get("data").directory);

		var rar4 = ArchiveFormats.openFile("mods/rar4_mod.rar");
		check("opens RAR4 archives", rar4.format == "rar" && rar4.getUnsupportedEntries().length == 0);
		check("converts RAR4 backslash paths", text(rar4.read("data/info.json")).indexOf("rar4") != -1);

		var compressed = ArchiveFormats.openFile("mods/compressed_mod.rar");
		var unsupported = compressed.getUnsupportedEntries();
		check("flags compressed RAR entries", unsupported.length == 1 && unsupported[0].unsupportedReason.indexOf("Store") != -1);
		check("refuses to read compressed RAR entries", throws(() -> compressed.read("_polymod_meta.json")));

		var bytes = sys.io.File.getBytes("mods/rar5_mod.rar");
		var memory = ArchiveFormats.openBytes(bytes, "memory.rar");
		check("opens archives from memory", memory.has("_polymod_meta.json"));

		var corrupted = bytes.sub(0, bytes.length);
		corrupted.set(corrupted.length - 30, corrupted.get(corrupted.length - 30) ^ 0xFF);
		check("detects corrupted data", throws(() -> ArchiveFormats.openBytes(corrupted, "bad.rar").read("data/ação.txt"))
			|| throws(() -> ArchiveFormats.openBytes(corrupted, "bad.rar")));

		check("rejects unknown formats", throws(() -> ArchiveFormats.openBytes(Bytes.ofString("not an archive"), "x.zip")));
		check("blocks path traversal", Archive.normalizePath("../evil.txt") == null);
		check("normalizes paths", Archive.normalizePath(".\\data//info.json") == "data/info.json");
		check("recognizes archive extensions", ArchiveFormats.isArchivePath("Mod.RAR") && !ArchiveFormats.isArchivePath("mod.json"));
		check("inflate checks the expected size", throws(() -> ZipArchive.inflate(Bytes.alloc(4), 10)));
	}

	static function testModOptions():Void
	{
		var options = ModOptions.fromJsonString(sys.io.File.getContent("mods/options_mod/_polymod_meta.json"));
		check("parses priority", options.priority == 10);
		check("parses tags case-insensitively", options.hasTag("gameplay"));
		check("parses hidden", options.hidden);
		check("parses custom data", options.data.difficulty == "hard" && options.data.speed == 1.5);
		check("parses settings", options.settings.length == 5);
		check("reports invalid settings", options.errors.length == 1 && options.errors[0].indexOf("broken") != -1);

		var conflict = ModOptions.fromJsonString('{"incompatible": ["a", "b"], "loadAfter": "c", "platforms": ["windows", 5]}');
		check("accepts incompatible as a list", conflict.incompatible.get("a") == ModOptions.ANY_VERSION);
		check("accepts a single string as a list", conflict.loadAfter.join(",") == "c");
		check("reports wrong value types", conflict.errors.length == 1);

		var invalid = ModOptions.fromJsonString("{ not json");
		check("survives invalid JSON", invalid.errors.length == 1 && invalid.enabledByDefault);

		check("matches the current platform", Platform.matches(Platform.names) && Platform.matches([]));
		check("supports platform exclusions", !Platform.matches(["!" + Platform.names[0]]));
		check("rejects other platforms", !Platform.matches(["nintendo-switch"]));
	}

	static function testModSettings():Void
	{
		var options = ModOptions.fromJsonString(sys.io.File.getContent("mods/options_mod/_polymod_meta.json"));
		var settings = new ModSettings();
		settings.define("options_mod", options.settings);

		check("returns defaults", settings.get("options_mod", "lives") == 3 && settings.get("options_mod", "theme") == "dark");
		check("clamps numbers", settings.set("options_mod", "lives", 20) && settings.get("options_mod", "lives") == 9);
		check("rejects wrong types", !settings.set("options_mod", "lives", "many"));
		check("rejects non-integer ints", !settings.set("options_mod", "lives", 2.5));
		check("rejects unknown choices", !settings.set("options_mod", "theme", "blue"));
		check("trims long strings", settings.set("options_mod", "playerName", "Boyfriend123") && settings.get("options_mod", "playerName") == "Boyfrien");
		check("rejects unknown settings", !settings.set("options_mod", "missing", true) && settings.get("options_mod", "missing") == null);

		var restored = ModSettings.fromJson(settings.toJson());
		restored.define("options_mod", options.settings);
		check("survives a JSON round trip", restored.get("options_mod", "lives") == 9);

		restored.reset("options_mod", "lives");
		check("resets values", restored.get("options_mod", "lives") == 3 && restored.get("options_mod", "playerName") == "Boyfrien");

		var tampered = ModSettings.fromJson('{"options_mod":{"lives":"x","speed":99}}');
		tampered.define("options_mod", options.settings);
		check("validates loaded values", tampered.get("options_mod", "lives") == 3 && tampered.get("options_mod", "speed") == 2.0);
	}

	static function testResolver():Void
	{
		var metadata:Map<String, ModMetadata> = [];
		var options:Map<String, ModOptions> = [];

		function add(id:String, version:String, ?json:Dynamic):Void
		{
			var meta = new ModMetadata();
			meta.id = id;
			meta.modVersion = version;
			metadata.set(id, meta);
			options.set(id, ModOptions.parse(json != null ? json : {}));
		}

		add("a", "1.0.0", {priority: 5});
		add("b", "1.0.0");
		add("c", "1.0.0", {loadBefore: ["b"]});
		add("d", "2.0.0", {incompatible: {a: "<2.0.0"}});
		add("e", "1.0.0", {gameVersion: ">=1.2.0"});
		add("f", "1.0.0", {loadAfter: ["g"]});
		add("g", "1.0.0", {loadAfter: ["f"]});

		var result = ModResolver.resolve(["a", "b", "c", "d", "e", "f", "g", "missing"], id -> metadata.get(id), id -> options.get(id), "1.0.0");
		check("skips incompatible mods", result.skipped.exists("d") && result.skipped.get("d").indexOf("\"a\"") != -1);
		check("skips mods for other game versions", result.skipped.exists("e"));
		check("skips missing mods", result.skipped.exists("missing"));
		check("applies loadBefore", result.order.indexOf("c") < result.order.indexOf("b"));
		check("applies priority", result.order[result.order.length - 1] == "a");
		check("reports circular order rules", result.warnings.length == 1 && result.order.contains("f") && result.order.contains("g"));
	}

	static function testPolymodExtended():Void
	{
		var loaded = PolymodExtended.init({
			modRoot: "mods",
			framework: Framework.CUSTOM,
			customBackend: TestBackend,
			gameVersion: "1.0.0",
			modListFile: '$OUT/modlist.json',
			settingsFile: '$OUT/settings.json'
		});

		var available = [for (mod in PolymodExtended.availableMods) mod.id];
		check("scans folders and archives", available.length == 11 && available.contains("zip_mod") && available.contains("rar4_mod")
			&& available.contains("rar5_mod"));
		check("skips unreadable archives", !available.contains("compressed_mod") && hasLogged(ArchiveFileSystem.ARCHIVE_UNSUPPORTED));
		check("uses archive file system by default", Std.isOfType(PolymodExtended.fileSystem, ArchiveFileSystem));
		check("detects single root folders in archives", PolymodExtended.fileSystem.exists("mods/zip_mod/_polymod_meta.json"));
		check("ignores macOS junk files", !PolymodExtended.fileSystem.exists("mods/zip_mod/__MACOSX"));
		check("reads files inside archives", PolymodExtended.fileSystem.getFileContent("mods/rar5_mod/data/info.json").indexOf("rar5") != -1);
		check("lists archive directories", PolymodExtended.fileSystem.readDirectory("mods/rar4_mod/data").contains("info.json"));
		check("hides archive files in the mod root", !PolymodExtended.fileSystem.readDirectory("mods").contains("zip_mod.zip"));

		var ids = PolymodExtended.getLoadedModIds();
		check("loads every compatible mod", ids.length == 7 && loaded.length == 7);
		check("skips other platforms", PolymodExtended.getSkipReason("android_only_mod") != null);
		check("skips other game versions", PolymodExtended.getSkipReason("future_mod") != null);
		check("skips incompatible mods", PolymodExtended.getSkipReason("zz_conflict_mod") != null);
		check("respects enabledByDefault", !PolymodExtended.modList.isEnabled("disabled_default_mod") && !ids.contains("disabled_default_mod"));
		check("loads dependencies first", ids.indexOf("base_mod") < ids.indexOf("addon_mod"));
		check("applies loadAfter", ids.indexOf("zip_mod") < ids.indexOf("a_after_mod"));
		check("applies priority", ids.indexOf("options_mod") > ids.indexOf("rar5_mod") && ids.indexOf("options_mod") > ids.indexOf("zip_mod"));

		check("exposes custom data", PolymodExtended.getModData("options_mod").difficulty == "hard");
		check("filters by tag", PolymodExtended.getModsByTag("GAMEPLAY").length == 1);
		check("hides hidden mods", PolymodExtended.getVisibleMods().filter(mod -> mod.id == "options_mod").length == 0);

		var changes = 0;
		PolymodExtended.onSettingChanged.add(_ -> changes++);
		check("reads setting defaults", PolymodExtended.getSetting("options_mod", "showIntro") == true);
		check("writes settings", PolymodExtended.setSetting("options_mod", "speed", 1.75) && PolymodExtended.getSetting("options_mod", "speed") == 1.75);
		check("rejects invalid settings", !PolymodExtended.setSetting("options_mod", "speed", "fast") && changes == 1);
		check("autosaves settings", sys.FileSystem.exists('$OUT/settings.json')
			&& sys.io.File.getContent('$OUT/settings.json').indexOf("1.75") != -1);

		var archiveFs = cast(PolymodExtended.fileSystem, ArchiveFileSystem);
		check("mounts archives from memory", archiveFs.mountBytes(sys.io.File.getBytes("fixtures/memory_mod.zip"), "memory_mod.zip"));
		PolymodExtended.reload();
		check("keeps memory archives after reload", PolymodExtended.isModLoaded("memory_mod"));
		check("unmounts archives", archiveFs.unmount("memory_mod") && !archiveFs.exists("mods/memory_mod/data/info.json"));
		PolymodExtended.reload();
		check("forgets unmounted archives", !PolymodExtended.isModLoaded("memory_mod"));

		PolymodExtended.setModEnabled("base_mod", false, true);
		ids = PolymodExtended.getLoadedModIds();
		check("unloads disabled mods", !ids.contains("base_mod"));
		check("drops mods with missing dependencies", !ids.contains("addon_mod"));
		check("loads mods that are no longer in conflict", ids.contains("zz_conflict_mod"));
		check("autosaves the mod list", !ModList.fromJson(sys.io.File.getContent('$OUT/modlist.json')).isEnabled("base_mod"));

		PolymodExtended.init({
			modRoot: "mods",
			framework: Framework.CUSTOM,
			customBackend: TestBackend,
			gameVersion: "1.0.0",
			modListFile: '$OUT/modlist.json',
			settingsFile: '$OUT/settings.json'
		});
		check("restores the mod list from disk", !PolymodExtended.modList.isEnabled("base_mod"));
		check("restores settings from disk", PolymodExtended.getSetting("options_mod", "speed") == 1.75);

		PolymodExtended.unloadAll();
		check("unloads everything", PolymodExtended.loadedMods.length == 0);

		var errors = PolymodExtended.log.filter(ERROR).filter(error -> error.code != ArchiveFileSystem.ARCHIVE_UNSUPPORTED);
		check("logs no unexpected errors", errors.length == 0);

		for (error in errors)
			Sys.println('  ${error.code}: ${error.message}');
	}

	static function testDesktopMods():Void
	{
		var root = '$OUT/desktop_mods';
		sys.FileSystem.createDirectory(root);
		sys.FileSystem.createDirectory('$root/base_mod');
		sys.io.File.copy("mods/base_mod/_polymod_meta.json", '$root/base_mod/_polymod_meta.json');

		PolymodExtended.init({
			modRoot: root,
			framework: Framework.CUSTOM,
			customBackend: TestBackend,
			modListFile: '$root/modlist.json'
		});
		check("starts with the copied mod", PolymodExtended.getLoadedModIds().join(",") == "base_mod");

		var opened:Array<String> = [];
		DesktopMods.opener = path -> {
			opened.push(path);
			return true;
		};
		check("opens the mods folder", DesktopMods.openModsFolder() && StringTools.endsWith(opened[0], "desktop_mods"));
		check("opens a mod folder", DesktopMods.openModFolder("base_mod") && StringTools.endsWith(opened[1], "base_mod"));

		var created = DesktopMods.createMod("created_mod", {title: "Created", folders: ["data"], extra: {priority: 3}});
		check("creates mod templates", created.success && sys.FileSystem.isDirectory('$root/created_mod/data') && PolymodExtended.isModLoaded("created_mod"));
		check("writes extra metadata", PolymodExtended.getModOptions("created_mod").priority == 3);
		check("rejects invalid ids", !DesktopMods.createMod("bad id!").success);
		check("rejects duplicate mods", !DesktopMods.createMod("created_mod").success);

		sys.io.File.saveContent('$root/created_mod/data/info.json', '{"name": "created"}');
		var exported = DesktopMods.exportMod("created_mod", '$OUT/export/created_mod.zip');
		var zip = exported.success ? ArchiveFormats.openFile('$OUT/export/created_mod.zip') : null;
		check("exports folder mods as zip", zip != null && text(zip.read("data/info.json")).indexOf("created") != -1 && zip.has("_polymod_meta.json"));

		var duplicate = DesktopMods.installMod('$OUT/export/created_mod.zip');
		check("refuses to overwrite installed mods", !duplicate.success && duplicate.error.indexOf("already installed") != -1);

		var replaced = DesktopMods.installMod('$OUT/export/created_mod.zip', {replace: true});
		check("replaces mods when asked", replaced.success && DesktopMods.isArchiveMod("created_mod") && !sys.FileSystem.exists('$root/created_mod'));
		check("replaced mods load from the archive", PolymodExtended.isModLoaded("created_mod"));

		var rar = DesktopMods.installMod("mods/rar5_mod.rar");
		check("installs rar mods", rar.success && sys.FileSystem.exists('$root/rar5_mod.rar') && PolymodExtended.isModLoaded("rar5_mod"));

		var folder = DesktopMods.installMod("mods/addon_mod", {enable: false});
		check("installs folder mods", folder.success && sys.FileSystem.exists('$root/addon_mod/data/info.json'));
		check("respects the enable option", !PolymodExtended.isModLoaded("addon_mod") && !PolymodExtended.modList.isEnabled("addon_mod"));

		var compressed = DesktopMods.installMod("mods/compressed_mod.rar");
		check("explains why archives cannot be installed", !compressed.success && compressed.error.indexOf("Store") != -1);
		check("rejects files that are not mods", !DesktopMods.installMod("mods/base_mod/_polymod_meta.json").success);

		var removed:Array<String> = [];
		DesktopMods.onUninstalled.add(id -> removed.push(id));
		check("uninstalls archive mods", DesktopMods.uninstallMod("rar5_mod") && !sys.FileSystem.exists('$root/rar5_mod.rar'));
		check("uninstalls folder mods", DesktopMods.uninstallMod("addon_mod") && !sys.FileSystem.exists('$root/addon_mod'));
		check("unloads uninstalled mods", !PolymodExtended.isModLoaded("rar5_mod") && removed.join(",") == "rar5_mod,addon_mod");
		check("fails to uninstall missing mods", !DesktopMods.uninstallMod("nothing_here"));

		var changes:Array<String> = [];
		DesktopMods.onModsChanged.add(changed -> changes = changed);
		DesktopMods.startWatching(1.0);
		check("watcher waits for the interval", !DesktopMods.update(0.5));
		check("watcher ignores unchanged folders", !DesktopMods.update(0.6));

		sys.FileSystem.createDirectory('$root/watched_mod');
		sys.io.File.saveContent('$root/watched_mod/_polymod_meta.json',
			'{"id": "watched_mod", "title": "Watched", "api_version": "0.1.0", "mod_version": "1.0.0"}');
		check("watcher detects new mods", DesktopMods.update(1.0) && changes.contains("watched_mod/_polymod_meta.json"));
		check("watcher reloads automatically", PolymodExtended.isModLoaded("watched_mod"));

		PolymodExtended.setModEnabled("watched_mod", false);
		check("watcher ignores the saved mod list", !DesktopMods.update(1.0));
		DesktopMods.stopWatching();
		check("stops watching", DesktopMods.watcher == null && !DesktopMods.update(5));
	}

	static function testOrganization():Void
	{
		var root = '$OUT/org_mods';

		mod('$root/plain_mod', "plain_mod");
		write('$root/plain_mod/data/info.json', '{"name": "plain"}');
		mod('$root/skin_mod', "skin_mod", '"category": "Skins"');
		write('$root/songs/_category.json', '{"title": "Song Packs", "description": "Extra songs", "order": 1}');
		mod('$root/songs/song_pack', "song_pack");
		write('$root/songs/song_pack/data/info.json', '{"name": "song pack"}');
		mod('$root/songs/duplicate', "plain_mod");
		sys.io.File.copy("fixtures/memory_mod.zip", '$root/songs/zip_in_cat.zip');
		write('$root/empty_cat/_category.json', '{"title": "Empty"}');

		mod('$root/psych_mod', "psych_mod");
		write('$root/psych_mod/pack.json', '{}');
		write('$root/psych_mod/characters/bf.json', '{"name": "psych bf"}');
		write('$root/psych_mod/weeks/week1.json', '{"name": "week 1"}');
		write('$root/psych_mod/songs/tutorial/Inst.ogg', "psych inst");

		mod('$root/codename_mod', "codename_mod");
		write('$root/codename_mod/data/weeks/weeks/week1.xml', "<week/>");
		write('$root/codename_mod/songs/bopeebo/song/Inst.ogg', "codename inst");

		mod('$root/mapped_mod', "mapped_mod", '"layout": "vslice", "folders": {"art": "images", "art/ui": "images/menus"}');
		write('$root/mapped_mod/art/logo.png', "logo");
		write('$root/mapped_mod/art/ui/button.png', "button");

		mod('$root/messy_mod', "messy_mod", '"layout": "vslice"');
		for (file in ["bf.png", "bf.xml", "Inst.ogg", "script.hxc", "notes.json", "README.md", "stuff/menu.png", "images/oops.ogg", "assets/sounds/hit.ogg"])
			write('$root/messy_mod/$file', file);

		var loaded = PolymodExtended.init({
			modRoot: root,
			framework: Framework.CUSTOM,
			customBackend: TestBackend,
			modListFile: '$root/modlist.json',
			structure: StructurePresets.vslice(),
			gameLayout: "vslice"
		});
		var fs = PolymodExtended.fileSystem;

		check("finds mods inside category folders", PolymodExtended.getMod("song_pack") != null && PolymodExtended.isModLoaded("song_pack"));
		check("finds archives inside category folders", PolymodExtended.isModLoaded("memory_mod")
			&& fs.getFileContent('$root/songs/zip_in_cat/data/info.json').indexOf("memory") != -1);
		check("reads category metadata", PolymodExtended.getCategory("songs") != null && PolymodExtended.getCategory("songs").title == "Song Packs");
		check("lists mods per category", PolymodExtended.getModsInCategory("songs").map(mod -> mod.id).join(",") == "memory_mod,song_pack");
		check("keeps empty categories with metadata", PolymodExtended.getCategory("empty_cat") != null);
		check("supports declared categories", PolymodExtended.getModCategory("skin_mod") != null && !PolymodExtended.getModCategory("skin_mod").folder);
		check("lists uncategorized mods", PolymodExtended.getUncategorizedMods().filter(mod -> mod.id == "plain_mod").length == 1);
		check("orders categories", PolymodExtended.categories[0].id == "empty_cat" || PolymodExtended.categories[0].order <= PolymodExtended.categories[1].order);
		check("ignores duplicate mod ids", hasLogged(PolymodExtended.MOD_DUPLICATE_ID) && PolymodExtended.getMod("plain_mod").dirName == "plain_mod");

		section("Folder layouts");
		check("detects Psych mods", PolymodExtended.getModLayout("psych_mod") == "psych");
		check("detects Codename mods", PolymodExtended.getModLayout("codename_mod") == "codename");
		check("maps Psych characters to the game layout", fs.getFileContent('$root/psych_mod/data/characters/bf.json').indexOf("psych bf") != -1);
		check("maps Psych weeks to levels", fs.exists('$root/psych_mod/data/levels/week1.json'));
		check("lists mapped folders", fs.readDirectory('$root/psych_mod/data').contains("characters") && fs.isDirectory('$root/psych_mod/data/levels'));
		check("keeps original paths readable", fs.exists('$root/psych_mod/characters/bf.json'));
		check("maps wildcard song folders", fs.getFileContent('$root/codename_mod/songs/bopeebo/Inst.ogg') == "codename inst");
		check("lists wildcard folders", fs.readDirectory('$root/codename_mod/songs/bopeebo').contains("Inst.ogg"));
		check("applies custom folder mappings", fs.getFileContent('$root/mapped_mod/images/logo.png') == "logo"
			&& fs.getFileContent('$root/mapped_mod/images/menus/button.png') == "button");
		check("includes mapped files in recursive listings", fs.readDirectoryRecursive('$root/mapped_mod').contains("images/menus/button.png"));
		check("exposes the active mappings", PolymodExtended.getFolderMappings("psych_mod").length == 3);
		check("builds layout mappings", FolderLayouts.mappings("psych", "codename").filter(m -> m.from == "songs/*" && m.to == "songs/*/song").length == 1);

		var mapper = new FolderMapper();
		check("rejects unbalanced wildcards", mapper.set("mods/x", [{from: "songs/*", to: "music"}]).length == 1 && !mapper.hasMappings());

		section("Structure validation");
		var issues = PolymodExtended.getStructureIssues("messy_mod");
		var suggestions:Map<String, String> = [for (issue in issues) if (issue.suggestion != null) issue.path => issue.suggestion];
		check("flags loose files", suggestions.get("bf.png") == "images/bf.png" && suggestions.get("script.hxc") == "scripts/script.hxc");
		check("keeps atlas files next to their image", suggestions.get("bf.xml") == "images/bf.xml");
		check("sends loose data files to data", suggestions.get("notes.json") == "data/notes.json");
		check("recognizes song audio", suggestions.get("Inst.ogg") == "songs/Inst.ogg");
		check("flags wrong extensions", suggestions.get("images/oops.ogg") == "sounds/oops.ogg");
		check("flags unknown folders", suggestions.get("stuff/menu.png") == "images/menu.png");
		check("unwraps assets folders", suggestions.get("assets/sounds/hit.ogg") == "sounds/hit.ogg");
		check("allows readme files", !suggestions.exists("README.md") && issues.filter(issue -> issue.path == "README.md").length == 0);
		check("logs structure warnings", hasLogged(PolymodExtended.MOD_STRUCTURE));
		check("validates clean mods", PolymodExtended.getStructureIssues("plain_mod").length == 0);

		var custom = ModStructure.fromJson('{"name": "strict", "folders": [{"path": "data", "extensions": ["json"], "required": true}, "images"]}');
		var customIssues = custom.validate(["images/a.png", "data/b.txt"]);
		check("loads structures from JSON", customIssues.filter(issue -> issue.kind == WRONG_EXTENSION).length == 1);
		check("reports missing required folders", custom.validate(["images/a.png"]).filter(issue -> issue.kind == MISSING_FOLDER).length == 1);
		check("has engine presets", StructurePresets.get("psych").hasFolder("custom_notetypes") && StructurePresets.get("codename") != null);

		section("Auto-organize");
		var plan = ModOrganizer.planMod("messy_mod");
		check("plans moves without touching files", plan.moves.length == 8 && sys.FileSystem.exists('$root/messy_mod/bf.png'));
		check("refuses archive mods", ModOrganizer.planMod("memory_mod").error != null);

		var organized = ModOrganizer.organizeMod("messy_mod");
		check("moves files into the right folders", organized.success && organized.moved.length == 8
			&& sys.FileSystem.exists('$root/messy_mod/images/bf.xml') && sys.FileSystem.exists('$root/messy_mod/sounds/hit.ogg'));
		check("removes emptied folders", !sys.FileSystem.exists('$root/messy_mod/stuff') && !sys.FileSystem.exists('$root/messy_mod/assets'));
		check("organized mods validate cleanly", PolymodExtended.getStructureIssues("messy_mod").length == 0);

		write('$root/messy_mod/extra.png', "a");
		write('$root/messy_mod/images/extra.png', "b");
		var conflict = ModOrganizer.planMod("messy_mod");
		check("never overwrites files", conflict.moves.length == 0 && conflict.skipped.length == 1);

		section("Category management");
		check("creates categories", DesktopMods.createCategory("maps", "Maps").success && PolymodExtended.getCategory("maps").title == "Maps");
		var created = DesktopMods.createMod("map_mod", {category: "maps"});
		check("creates mods inside categories", created.success && PolymodExtended.getModCategory("map_mod").id == "maps");
		check("uses the structure for new mods", sys.FileSystem.exists('$root/maps/map_mod/data') && sys.FileSystem.exists('$root/maps/map_mod/images'));

		var moved = DesktopMods.moveModToCategory("skin_mod", "skins");
		check("moves folder mods between categories", moved.success && PolymodExtended.getModCategory("skin_mod").id == "skins"
			&& PolymodExtended.isModLoaded("skin_mod"));

		var movedArchive = DesktopMods.moveModToCategory("memory_mod", null);
		check("moves archive mods out of categories", movedArchive.success && sys.FileSystem.exists('$root/zip_in_cat.zip')
			&& PolymodExtended.isModLoaded("memory_mod") && PolymodExtended.getModCategory("memory_mod") == null);

		var installed = DesktopMods.installMod("mods/rar4_mod.rar", {category: "songs"});
		check("installs into categories", installed.success && PolymodExtended.getModCategory("rar4_mod").id == "songs");
		check("rejects invalid category names", !DesktopMods.createCategory("../evil").success);
		check("loaded every compatible mod", loaded.length > 0 && !PolymodExtended.log.hasErrors());
	}

	static function testAppSettings():Void
	{
		var root = '$OUT/app_mods';
		mod('$root/theme_mod', "theme_mod", '"app": {"title": "Cool Mod", "fps": 999, "backgroundColor": "#112233", "icon": "icon.png", "width": "big", "secret": 1}');
		write('$root/theme_mod/icon.png', "fake png");
		mod('$root/second_mod', "second_mod", '"app": {"title": "Second", "fullscreen": true}');

		var changes = 0;
		ModAppSettings.onChanged.add(_ -> changes++);

		PolymodExtended.init({modRoot: root, framework: Framework.CUSTOM, customBackend: TestBackend});
		check("blocks settings the game did not allow", ModAppSettings.get("title") == null && hasLogged(ModAppSettings.APP_SETTING_BLOCKED));

		PolymodExtended.init({modRoot: root, framework: Framework.CUSTOM, customBackend: TestBackend, allowAppSettings: true});
		check("applies allowed settings", ModAppSettings.get("title") == "Cool Mod" && ModAppSettings.getSource("title") == "theme_mod");
		check("later mods win", ModAppSettings.get("fullscreen") == true && ModAppSettings.getSource("fullscreen") == "second_mod");
		check("clamps numbers", ModAppSettings.get("fps") == 360);
		check("parses colors", ModAppSettings.get("backgroundColor") == 0xFF112233);
		check("loads files from the mod", ModAppSettings.values.get("icon").bytes.toString() == "fake png");
		check("rejects invalid values", ModAppSettings.get("width") == null && hasLogged(ModAppSettings.APP_SETTING_INVALID));
		check("ignores unknown keys", ModAppSettings.get("secret") == null);
		check("notifies changes", changes > 0);

		PolymodExtended.setModEnabled("theme_mod", false, true);
		check("updates when mods are disabled", ModAppSettings.get("title") == "Second" && ModAppSettings.get("fps") == null);

		ModAppSettings.allow("speed", {type: FLOAT, min: 0.5, max: 2});
		check("supports custom rules", ModAppSettings.rules.exists("speed"));
		check("parses short and long colors", ModAppSettings.parseColor("0x80FF0000") == 0x80FF0000 && ModAppSettings.parseColor("nope") == null);
		ModAppSettings.block("speed");
	}

	static function testHooks():Void
	{
		ModHooks.clear();
		var calls:Array<String> = [];

		ModHooks.add("songStart", event -> calls.push("low"), null, -5);
		ModHooks.add("songStart", event -> calls.push("high"), "some_mod", 10);
		ModHooks.add("songStart", event -> calls.push("normal:" + event.data.song));
		var event = ModHooks.call("songStart", {song: "bopeebo"});
		check("calls listeners by priority", calls.join(",") == "high,normal:bopeebo,low");
		check("passes event data", !event.cancelled);

		ModHooks.add("noteHit", event -> event.cancel(), "a_mod", 5);
		ModHooks.add("noteHit", event -> event.stopPropagation(), "a_mod", 1);
		ModHooks.add("noteHit", event -> calls.push("never"));
		var hit = ModHooks.call("noteHit");
		check("cancels events", hit.cancelled);
		check("stops propagation", !calls.contains("never"));
		check("respects non-cancelable events", !ModHooks.call("noteHit", null, false).cancelled);

		var onceCalls = 0;
		ModHooks.once("pause", _ -> onceCalls++);
		ModHooks.call("pause");
		ModHooks.call("pause");
		check("runs once listeners once", onceCalls == 1 && !ModHooks.has("pause"));

		ModHooks.add("broken", _ -> throw "script error", "buggy_mod");
		for (i in 0...3)
			ModHooks.call("broken");
		check("survives listener errors", hasLogged(ModHooks.MOD_HOOK_ERROR));
		check("removes listeners that keep failing", !ModHooks.has("broken"));

		var loaded:Array<String> = [];
		ModHooks.add(PolymodExtended.HOOK_MODS_LOADED, event -> loaded = [for (mod in (event.data : Array<ModMetadata>)) mod.id]);
		PolymodExtended.reload();
		check("clears mod listeners on reload", ModHooks.count("songStart") == 2 && ModHooks.count("noteHit") == 1);
		check("fires modsLoaded", loaded.contains("second_mod"));
		ModHooks.clear();
	}

	static function testRoots():Void
	{
		var primary = '$OUT/root_a';
		var extra = '$OUT/root_b';

		mod('$primary/a_mod', "a_mod");
		mod('$primary/songs/primary_song', "primary_song");
		mod('$extra/b_mod', "b_mod");
		write('$extra/b_mod/data/info.json', '{"name": "b"}');
		sys.io.File.copy("mods/zip_mod.zip", '$extra/zip_mod.zip');
		mod('$extra/songs/extra_song', "extra_song");
		mod('$extra/skins/skin_x', "skin_x");
		mod('$extra/a_mod', "a_mod_copy");

		PolymodExtended.init({
			modRoot: primary,
			modRoots: [extra],
			framework: Framework.CUSTOM,
			customBackend: TestBackend
		});

		var ids = PolymodExtended.getLoadedModIds();
		check("loads mods from every root", ["a_mod", "b_mod", "zip_mod", "primary_song", "extra_song", "skin_x"].filter(id -> !ids.contains(id)).length == 0);
		check("merges categories across roots", PolymodExtended.getModsInCategory("songs").length == 2);
		check("links whole categories", PolymodExtended.getModCategory("skin_x").id == "skins");
		check("primary root wins conflicts", !ids.contains("a_mod_copy") && hasLogged(ArchiveFileSystem.ARCHIVE_CONFLICT));
		check("reads files from extra roots", PolymodExtended.fileSystem.getFileContent('$primary/b_mod/data/info.json') == '{"name": "b"}');

		var location = DesktopMods.getModLocation("b_mod");
		check("finds the real folder", location != null && StringTools.startsWith(haxe.io.Path.normalize(location), haxe.io.Path.normalize(extra)));
		check("finds the real archive", DesktopMods.getModLocation("zip_mod") == haxe.io.Path.join([extra, "zip_mod.zip"]));

		DesktopMods.startWatching(0.1);
		mod('$extra/late_mod', "late_mod");
		check("watches extra roots", DesktopMods.update(0.2) && PolymodExtended.isModLoaded("late_mod"));
		DesktopMods.stopWatching();

		check("uninstalls from extra roots", DesktopMods.uninstallMod("b_mod") && !sys.FileSystem.exists('$extra/b_mod'));

		var user = ModPaths.userRoot("My: Game");
		check("builds a user mods folder", StringTools.endsWith(haxe.io.Path.normalize(user), "My_ Game/mods"));
		check("lists default roots", ModPaths.defaultRoots("My Game").length >= 1);
		check("sanitizes folder names", ModPaths.sanitize("a:b/c.") == "a_b_c");
		check("checks write access", ModPaths.isWritable('$OUT/writable') && sys.FileSystem.exists('$OUT/writable'));
		check("android shared folder", ModPaths.androidSharedRoot("FNF Mods") == "/storage/emulated/0/FNF Mods/mods");

		var rules = new ModStructure("rules", [{path: "data"}]);
		rules.requiredRootFiles = ["_polymod_meta.json", "credits.txt"];
		rules.recommendedRootFiles = ["_polymod_icon.png"];
		var rootIssues = rules.validate(["_polymod_meta.json", "data/a.json"]);
		check("requires root files", rootIssues.filter(issue -> issue.kind == MISSING_ROOT_FILE && issue.path == "credits.txt" && issue.recommended != true).length == 1);
		check("recommends root files", rootIssues.filter(issue -> issue.path == "_polymod_icon.png" && issue.recommended == true).length == 1);
		check("loads root file rules from JSON", ModStructure.fromJson('{"folders": ["data"], "requiredRootFiles": ["Pack.json"]}').requiredRootFiles[0] == "Pack.json");
	}

	static function png(width:Int, height:Int, colorType:Int = 6):Bytes
	{
		var output = new haxe.io.BytesOutput();
		output.bigEndian = true;
		for (b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
			output.writeByte(b);
		output.writeInt32(13);
		output.writeString("IHDR");
		output.writeInt32(width);
		output.writeInt32(height);
		output.writeByte(8);
		output.writeByte(colorType);
		output.writeByte(0);
		output.writeByte(0);
		output.writeByte(0);
		output.writeInt32(0);
		output.writeInt32(0);
		output.writeString("IEND");
		output.writeInt32(0);
		return output.getBytes();
	}

	static function testImages():Void
	{
		var root = '$OUT/image_mods';
		mod('$root/base_img', "base_img");
		sys.io.File.saveBytes(mkdirs('$root/base_img/images/characters/bf.png'), png(64, 32));
		write('$root/base_img/images/characters/bf.xml', '<?xml version="1.0"?><TextureAtlas imagePath="bf.png">'
			+ '<SubTexture name="BF idle0000" x="0" y="0" width="32" height="32"/>'
			+ '<SubTexture name="BF idle0001" x="32" y="0" width="32" height="32" frameX="-2" frameY="-1" frameWidth="36" frameHeight="34"/>'
			+ '<SubTexture name="BF NOTE LEFT0000" x="0" y="0" width="16" height="32" rotated="true"/></TextureAtlas>');
		sys.io.File.saveBytes(mkdirs('$root/base_img/images/ui/logo.png'), png(100, 50));
		mod('$root/zz_override', "zz_override", '"images": {"characters/gf": "characters/bf", "ui/title": "ui/logo"}');
		sys.io.File.saveBytes(mkdirs('$root/zz_override/images/ui/logo.png'), png(200, 100, 2));
		mod('$root/bad_img', "bad_img");
		write('$root/bad_img/images/broken.png', "not a png");
		sys.io.File.saveBytes(mkdirs('$root/bad_img/images/huge.png'), png(9000, 10));
		sys.io.File.saveBytes(mkdirs('$root/bad_img/images/frames.png'), png(10, 10));
		write('$root/bad_img/images/frames.xml', '<TextureAtlas><SubTexture name="a0000" x="5" y="5" width="10" height="10"/></TextureAtlas>');
		write('$root/bad_img/images/orphan.xml', '<TextureAtlas></TextureAtlas>');

		PolymodExtended.init({modRoot: root, framework: Framework.CUSTOM, customBackend: TestBackend});

		check("later mods override images", ModImages.getSource("ui/logo") == "zz_override" && ModImages.getInfo("ui/logo").width == 200);
		check("accepts paths with folder and extension", ModImages.resolve("images/characters/bf.png").modId == "base_img");
		check("follows image aliases", ModImages.resolve("characters/gf").id == "characters/bf" && ModImages.getInfo("ui/title").width == 200);
		check("reads PNG details", ModImages.getInfo("characters/bf").height == 32 && ModImages.getInfo("characters/bf").hasAlpha
			&& !ModImages.getInfo("ui/logo").hasAlpha);
		check("returns null for missing images", ModImages.resolve("nothing/here") == null && ModImages.getBytes("nothing") == null);

		var atlas = ModImages.getAtlas("characters/bf");
		check("loads the atlas next to the image", atlas != null && atlas.format == SPARROW && atlas.frames.length == 3);
		check("reads frame offsets", atlas.getFrame("BF idle0001").frameX == -2 && atlas.getFrame("BF idle0001").frameWidth == 36);
		check("groups animations", atlas.getAnimationNames().join(",") == "BF idle,BF NOTE LEFT" && atlas.getAnimationFrames("BF idle").length == 2);
		check("finds atlases through aliases", ModImages.getAtlas("characters/gf") != null);

		check("lists images", ModImages.list().contains("ui/logo") && ModImages.list("characters").join(",") == "characters/bf");
		check("lists overridden images", ModImages.getOverrides().filter(o -> o.id == "ui/logo" && o.mods.join(",") == "base_img,zz_override").length == 1);

		var issues = ModImages.validateMod("bad_img").map(issue -> issue.message).join("\n");
		check("flags invalid images", issues.indexOf('"broken" is not a valid image') != -1);
		check("flags oversized images", issues.indexOf("larger than the 8192px limit") != -1);
		check("flags frames outside the image", issues.indexOf('outside the image, like "a0000"') != -1);
		check("flags atlases without images", issues.indexOf('"orphan.xml" has no image') != -1);
		check("clean mods have no image issues", ModImages.validateMod("base_img").length == 0);

		PolymodExtended.setModEnabled("zz_override", false, true);
		check("clears the cache on reload", ModImages.getSource("ui/logo") == "base_img" && ModImages.resolve("characters/gf") == null);

		var packer = ImageAtlas.parse("arrow0 = 0 0 10 20\narrow1 = 10 0 10 20\n");
		check("parses sprite sheet packer atlases", packer.format == PACKER && packer.frames[1].x == 10 && packer.getAnimationNames().join(",") == "arrow");
		var json = ImageAtlas.parse('{"frames": {"a.png": {"frame": {"x": 1, "y": 2, "w": 3, "h": 4}, "rotated": false, "spriteSourceSize": {"x": 1, "y": 1}, "sourceSize": {"w": 5, "h": 6}}}, "meta": {"image": "a.png"}}');
		check("parses TexturePacker JSON", json.format == JSON && json.frames[0].frameX == -1 && json.frames[0].frameHeight == 6 && json.imagePath == "a.png");
		var arrayJson = ImageAtlas.parse('{"frames": [{"filename": "b", "frame": {"x": 0, "y": 0, "w": 8, "h": 8}}]}');
		check("parses TexturePacker JSON arrays", arrayJson.frames[0].name == "b");
		var spritemap = ImageAtlas.parse('{"ATLAS": {"SPRITES": [{"SPRITE": {"name": "0000", "x": 2, "y": 3, "w": 4, "h": 5, "rotated": true}}]}, "meta": {"image": "spritemap1.png"}}');
		check("parses Animate spritemaps", spritemap.frames[0].rotated && spritemap.frames[0].height == 5 && spritemap.imagePath == "spritemap1.png");
		check("rejects broken atlases", throws(() -> ImageAtlas.parse("<NotAtlas/>")) && throws(() -> ImageAtlas.parse("garbage line")));

		var jpeg = Bytes.alloc(20);
		for (i => b in [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x01, 0x2C, 0x00, 0xC8])
			jpeg.set(i, b);
		var jpegInfo = ImageInfo.read(jpeg);
		check("reads JPEG sizes", jpegInfo != null && jpegInfo.type == JPEG && jpegInfo.width == 200 && jpegInfo.height == 300);
		check("detects powers of two", ImageInfo.isPowerOfTwo(512) && !ImageInfo.isPowerOfTwo(500));
	}

	static function testScripts():Void
	{
		var root = '$OUT/script_mods';
		mod('$root/a_script_mod', "a_script_mod", '"settings": [{"id": "volume", "type": "int", "default": 7}]');
		write('$root/a_script_mod/data/info.json', '{"name": "scripted"}');
		write('$root/a_script_mod/scripts/main.hx', "
			var counter = 0;
			var greeting = 'hi from ' + mod.id;
			function onCreate() { counter = 10; print('created', counter); }
			function add(a, b) { counter += a + b; return counter; }
			function onUpdate(elapsed) { counter += 1; }
			function onNoteHit(note) { return note == 'bad' ? STOP : CONTINUE; }
			function settingValue() { return mod.getSetting('volume'); }
			function readInfo() { return mod.readJson('data/info.json').name; }
			function onDestroy() { game.destroyed++; }
			hook('songStart', function(event) { event.data.calls++; });
		");
		write('$root/a_script_mod/scripts/notes.txt', "not a script");
		write('$root/a_script_mod/stages/stage1.hx', "function onBeat(beat) { return beat * 2; }");
		mod('$root/b_script_mod', "b_script_mod");
		write('$root/b_script_mod/scripts/other.hxs', "function add(a, b) { return -1; } function tryEscape() { return Type.resolveClass('Sys'); } function tryNew() { return new haxe.Http('x'); }");
		write('$root/b_script_mod/scripts/broken.hx', "function oops( {");

		var game = {destroyed: 0};
		ScriptSandbox.expose("game", game);

		var errors:Array<String> = [];
		var prints:Array<String> = [];
		ModScripts.onError.add(message -> errors.push(message.message));
		ModScripts.onPrint.add(message -> prints.push(message.message));

		PolymodExtended.init({modRoot: root, framework: Framework.CUSTOM, customBackend: TestBackend, scripts: true});

		check("loads scripts from every mod", ModScripts.global.scripts.length == 2);
		check("ignores files that are not scripts", ModScripts.global.scripts.filter(script -> script.name.indexOf("notes") != -1).length == 0);
		check("reports syntax errors", errors.length == 1 && hasLogged(ModScripts.MOD_SCRIPT_ERROR));
		check("runs onCreate", prints.join("|") == "created 10");

		var main = ModScripts.global.scripts[0];
		check("keeps top-level variables", main.get("greeting") == "hi from a_script_mod" && main.get("counter") == 10);
		check("calls functions in every script", ModScripts.call("add", [1, 2]).join(",") == "13,-1");
		check("functions update script variables", main.get("counter") == 13);
		ModScripts.update(0.5);
		check("calls onUpdate", main.get("counter") == 14);
		check("supports STOP", ModScripts.callStop("onNoteHit", ["bad"]) && !ModScripts.callStop("onNoteHit", ["good"]));
		check("gives scripts their mod settings", main.call("settingValue") == 7);
		check("lets scripts read their mod files", main.call("readInfo") == "scripted");
		check("lets scripts read exposed values", main.has("game"));

		var data = {calls: 0};
		polymod.extended.hooks.ModHooks.call("songStart", data);
		check("registers hooks from scripts", data.calls == 1);

		var other = ModScripts.global.scripts[1];
		errors = [];
		check("blocks unexposed classes", other.call("tryEscape") == null && errors.length == 1 && errors[0].indexOf("Type") != -1);
		check("blocks creating unexposed classes", other.call("tryNew") == null && errors.length == 2 && errors[1].indexOf("not available") != -1);

		var stage = ModScripts.load("stages/stage1.hx");
		check("loads scripts on demand", stage.scripts.length == 1 && stage.call("onBeat", [4])[0] == 8);
		check("on-demand scripts receive global calls", ModScripts.call("onBeat", [2]).contains(4));
		ModScripts.destroyGroup(stage);
		check("destroys script groups", !ModScripts.call("onBeat", [2]).contains(4));

		ScriptSandbox.exposeClass(haxe.io.BytesBuffer);
		var inlineScript = ModScripts.fromString("var buffer = new BytesBuffer(); buffer.addByte(65); function size() { return buffer.length; }", "inline");
		check("creates exposed classes", inlineScript.active && inlineScript.call("size") == 1);
		ScriptSandbox.hide("BytesBuffer");
		check("hides classes again", !ScriptSandbox.classes.exists("haxe.io.BytesBuffer"));

		PolymodExtended.reload();
		check("destroys scripts on reload", game.destroyed == 1 && ModScripts.global.scripts.length == 2);
		data.calls = 0;
		polymod.extended.hooks.ModHooks.call("songStart", data);
		check("does not duplicate hooks after reload", data.calls == 1);

		PolymodExtended.unloadAll();
		check("destroys scripts when unloading", game.destroyed == 2 && ModScripts.global.scripts.length == 0);
		ScriptSandbox.hide("game");
	}

	static function mkdirs(path:String):String
	{
		var directory = haxe.io.Path.directory(path);

		if (!sys.FileSystem.exists(directory))
			sys.FileSystem.createDirectory(directory);

		return path;
	}

	static function resolveWith(http:MockHttpClient, link:String, ?options:ResolveOptions):{?mod:ResolvedMod, ?error:String}
	{
		var result:{?mod:ResolvedMod, ?error:String} = {error: "no callback"};
		ModSources.resolve(link, options, mod -> result = {mod: mod}, error -> result = {error: error}, http);
		return result;
	}

	static function testSources():Void
	{
		var gameBanana = '{"_idRow": 707303, "_sName": "Infected Players", "_sVersion": "2.0", "_tsDateUpdated": 1791733059, "_aFiles": ['
			+ '{"_idRow": 1, "_sFile": "old.zip", "_sDownloadUrl": "https://gamebanana.com/dl/1", "_bIsArchived": true, "_sAvResult": "clean"},'
			+ '{"_idRow": 1845259, "_sFile": "players_blue.zip", "_nFilesize": 90348794, "_sDownloadUrl": "https://gamebanana.com/dl/1845259", '
			+ '"_sMd5Checksum": "5c67baec44c462374d99e63388b1f56e", "_bIsArchived": false, "_sAvResult": "clean", "_sVersion": "2.1"},'
			+ '{"_idRow": 1845267, "_sFile": "players_normal.zip", "_nFilesize": 89303480, "_sDownloadUrl": "https://gamebanana.com/dl/1845267", '
			+ '"_sMd5Checksum": "", "_bIsArchived": false, "_sAvResult": "clean"}]}';
		var release = '{"tag_name": "v1.2.0", "name": "Big Update", "published_at": "2026-05-01T10:00:00Z", "assets": ['
			+ '{"id": 11, "name": "source.txt", "browser_download_url": "https://github.com/me/mod/releases/download/v1.2.0/source.txt", "size": 3},'
			+ '{"id": 12, "name": "MyMod.zip", "browser_download_url": "https://github.com/me/mod/releases/download/v1.2.0/MyMod.zip", "size": 2048}]}';
		var http = new MockHttpClient([
			"https://gamebanana.com/apiv11/Mod/707303/ProfilePage" => gameBanana,
			"https://api.github.com/repos/me/mod/releases/latest" => release,
			"https://api.github.com/repos/me/norelease" => '{"default_branch": "develop"}',
			"https://www.mediafire.com/file/abc123/pack.zip/file" => '<a class="input popsok" aria-label="Download file" href="https://download1234.mediafire.com/xyz/abc123/pack.zip" id="downloadButton">Download</a>'
		]);

		var gb = resolveWith(http, "https://gamebanana.com/mods/707303");
		check("resolves GameBanana mod pages", gb.mod != null && gb.mod.url == "https://gamebanana.com/dl/1845259" && gb.mod.fileName == "players_blue.zip");
		check("reads GameBanana file details", gb.mod.md5 == "5c67baec44c462374d99e63388b1f56e" && gb.mod.size == 90348794 && gb.mod.version == "2.1"
			&& gb.mod.files.length == 2 && gb.mod.sourceId == "Mod/707303" && gb.mod.title == "Infected Players");
		check("picks GameBanana files by name", resolveWith(http, "https://gamebanana.com/mods/707303", {fileName: "players_normal.zip"}).mod.fileId == "1845267");
		check("ignores empty checksums", resolveWith(http, "https://gamebanana.com/mods/707303", {fileIndex: 1}).mod.md5 == null);
		check("accepts GameBanana download links", resolveWith(http, "https://gamebanana.com/dl/1845259").mod.fileId == "1845259");
		check("rejects other GameBanana pages", resolveWith(http, "https://gamebanana.com/members/1").error != null);

		var oneClick = ModSources.parseOneClick("funkin:https://gamebanana.com/mmdl/1845259,Mod,707303,zip");
		check("parses 1-click links", oneClick.scheme == "funkin" && oneClick.url == "https://gamebanana.com/mmdl/1845259" && oneClick.itemType == "Mod"
			&& oneClick.itemId == "707303" && oneClick.extension == "zip");
		check("resolves 1-click links", resolveWith(http, "funkin:https://gamebanana.com/mmdl/1845259,Mod,707303").mod.fileId == "1845259");

		var gh = resolveWith(http, "https://github.com/me/mod");
		check("resolves the latest GitHub release", gh.mod.url == "https://github.com/me/mod/releases/download/v1.2.0/MyMod.zip" && gh.mod.version == "v1.2.0");
		check("falls back to the repository zip", resolveWith(http, "https://github.com/me/norelease").mod.url
			== "https://codeload.github.com/me/norelease/zip/refs/heads/develop");
		check("downloads GitHub branches", resolveWith(http, "https://github.com/me/mod/tree/beta").mod.url == "https://codeload.github.com/me/mod/zip/refs/heads/beta");
		check("keeps direct GitHub downloads", resolveWith(http, "https://github.com/me/mod/releases/download/v1/a.zip").mod.version == "v1");

		check("converts Google Drive links", resolveWith(http, "https://drive.google.com/file/d/1AbC_dEf-2/view?usp=sharing").mod.url
			== "https://drive.usercontent.google.com/download?id=1AbC_dEf-2&export=download&confirm=t");
		check("reads Google Drive ids from queries", GoogleDriveSource.fileId("https://drive.google.com/open?id=XYZ_123") == "XYZ_123");
		check("rejects Google Drive folders", resolveWith(http, "https://drive.google.com/drive/folders/abc").error != null);
		check("converts Dropbox links", DropboxSource.directUrl("https://www.dropbox.com/scl/fi/abc/pack.zip?rlkey=k&dl=0") == "https://www.dropbox.com/scl/fi/abc/pack.zip?rlkey=k&dl=1");
		check("finds MediaFire download links", resolveWith(http, "https://www.mediafire.com/file/abc123/pack.zip/file").mod.url
			== "https://download1234.mediafire.com/xyz/abc123/pack.zip");
		check("reports missing MediaFire buttons", MediaFireSource.findDownloadLink("<html></html>") == null);

		check("keeps unknown links as direct downloads", resolveWith(http, "https://example.com/mods/pack.rar").mod.source == "direct");
		check("rejects things that are not links", resolveWith(http, "C:/mods/pack.zip").error != null);
		check("explains unsupported formats", ModSources.unsupportedArchiveMessage("pack.7z").indexOf(".7z") != -1);

		ModSources.corsProxy = "https://proxy.example/?url=";
		check("proxies blocked hosts", ModSources.proxied("https://gamebanana.com/dl/1") == "https://proxy.example/?url=https%3A%2F%2Fgamebanana.com%2Fdl%2F1");
		check("leaves other hosts alone", ModSources.proxied("https://example.com/a.zip") == "https://example.com/a.zip");
		ModSources.corsProxy = null;
	}

	static function testRemoteMods():Void
	{
		var server = new sys.io.Process("python3", ["fixtures/server.py"]);
		var port = Std.parseInt(server.stdout.readLine());
		var base = 'http://127.0.0.1:$port';
		var root = '$OUT/remote_mods';
		sys.FileSystem.createDirectory(root);

		PolymodExtended.init({
			modRoot: root,
			framework: Framework.CUSTOM,
			customBackend: TestBackend
		});

		var progress:Array<RemoteProgress> = [];
		RemoteMods.onProgress.add(event -> progress.push(event));

		var direct = RemoteMods.install('$base/mods/rar5_mod.rar');
		check("installs mods from links", direct.success && PolymodExtended.isModLoaded("rar5_mod") && sys.FileSystem.exists('$root/rar5_mod.rar'));
		check("reports download progress", progress.length > 0 && progress[progress.length - 1].ratio == 1);
		check("cleans up downloads", !sys.FileSystem.exists('$root/.downloads'));

		var named = RemoteMods.install('$base/named', {category: "links"});
		check("uses Content-Disposition names", named.success && named.id == "zip_mod" && sys.FileSystem.exists('$root/links/zip_mod.zip'));

		GameBananaSource.apiUrl = '$base/api';
		var gb = RemoteMods.install("https://gamebanana.com/mods/123");
		check("installs GameBanana mods through redirects", gb.success && gb.id == "memory_mod" && PolymodExtended.isModLoaded("memory_mod"));
		check("records the source", RemoteMods.getSource("memory_mod") != null && RemoteMods.getSource("memory_mod").fileId == "9001");

		var bad = RemoteMods.install("https://gamebanana.com/mods/124", {replace: true});
		check("rejects corrupted downloads", !bad.success && bad.error.indexOf("checksum") != -1);

		var limited = RemoteMods.install('$base/big.zip', {maxBytes: 1024});
		check("enforces the size limit", !limited.success && limited.error.indexOf("limit") != -1 && !sys.FileSystem.exists('$root/big.zip'));

		var missing = RemoteMods.install('$base/nothing.zip');
		check("reports HTTP errors", !missing.success && missing.error.indexOf("404") != -1);

		var duplicate = RemoteMods.install('$base/mods/rar5_mod.rar');
		check("refuses duplicates unless replacing", !duplicate.success && duplicate.error.indexOf("already installed") != -1);

		var updates = RemoteMods.checkUpdates();
		check("checks for updates", updates.filter(u -> u.id == "memory_mod" && !u.hasUpdate).length == 1);

		var http = new haxe.Http('$base/state/next');
		http.request(false);
		updates = RemoteMods.checkUpdates(["memory_mod"]);
		check("detects new versions", updates.length == 1 && updates[0].hasUpdate);

		var updated = RemoteMods.updateMod("memory_mod");
		check("updates mods in place", updated.success && RemoteMods.getSource("memory_mod").fileId == "9002" && PolymodExtended.isModLoaded("memory_mod"));
		check("keeps the category when updating", RemoteMods.updateMod("zip_mod").success && sys.FileSystem.exists('$root/links/zip_mod.zip'));

		DesktopMods.uninstallMod("memory_mod");
		check("forgets sources of uninstalled mods", RemoteMods.getSource("memory_mod") == null);

		var finished:RemoteInstallResult = null;
		RemoteMods.installAsync('$base/mods/rar4_mod.rar', null, result -> finished = result);
		var waited = 0.0;

		while (finished == null && waited < 10)
		{
			Sys.sleep(0.05);
			waited += 0.05;
			RemoteMods.update();
		}

		check("installs in the background", finished != null && finished.success && PolymodExtended.isModLoaded("rar4_mod"));

		server.close();
	}

	static function mod(path:String, id:String, ?extra:String):Void
	{
		write('$path/_polymod_meta.json', '{"id": "$id", "title": "$id", "api_version": "0.1.0", "mod_version": "1.0.0"' + (extra != null ? ', $extra' : "") + "}");
	}

	static function write(path:String, content:String):Void
	{
		var directory = haxe.io.Path.directory(path);

		if (directory.length > 0 && !sys.FileSystem.exists(directory))
			sys.FileSystem.createDirectory(directory);

		sys.io.File.saveContent(path, content);
	}

	static function hasLogged(code:String):Bool
	{
		for (entry in PolymodExtended.log.entries)
			if (entry.code == code)
				return true;

		return false;
	}

	static function throws(action:Void->Void):Bool
	{
		try
		{
			action();
			return false;
		}
		catch (e:Dynamic)
		{
			return true;
		}
	}

	static function text(bytes:Bytes):String
	{
		return bytes != null ? bytes.toString() : "";
	}

	static function clearOutput():Void
	{
		if (!sys.FileSystem.exists(OUT))
			return;

		deleteRecursive(OUT);
	}

	static function deleteRecursive(path:String):Void
	{
		if (sys.FileSystem.isDirectory(path))
		{
			for (name in sys.FileSystem.readDirectory(path))
				deleteRecursive('$path/$name');

			sys.FileSystem.deleteDirectory(path);
		}
		else
			sys.FileSystem.deleteFile(path);
	}

	static function section(name:String):Void
	{
		Sys.println('\n$name');
	}

	static function check(name:String, condition:Bool):Void
	{
		if (condition)
			passed++;
		else
			failed++;

		Sys.println((condition ? "  [PASS] " : "  [FAIL] ") + name);
	}
}
