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
import polymod.extended.desktop.DesktopMods;
import polymod.extended.desktop.ModOrganizer;
import polymod.extended.structure.FolderLayouts;
import polymod.extended.structure.FolderMapper;
import polymod.extended.structure.ModStructure;
import polymod.extended.structure.StructurePresets;
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
