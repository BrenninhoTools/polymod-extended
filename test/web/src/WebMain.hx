package;

import haxe.io.Bytes;
import js.lib.Promise;
import polymod.Polymod.Framework;
import polymod.extended.PolymodExtended;
import polymod.extended.fs.VirtualFileSystem;
import polymod.extended.util.Storage;
import polymod.extended.web.IndexedDBStore;
import polymod.extended.sources.GameBananaSource;
import polymod.extended.web.WebDownload;
import polymod.extended.web.WebDownload.DownloadProgress;
import polymod.extended.web.WebMods;
import polymod.extended.images.ModImages;
import polymod.extended.scripting.ModScripts;

class WebMain
{
	static var passed:Int = 0;
	static var failed:Int = 0;
	static var base:String;

	static function main():Void
	{
		

		startServer().then(port ->
		{
			base = 'http://127.0.0.1:$port';
			return run();
		}).then(_ -> runDownloads()).then(_ -> runSources()).then(_ -> runBackups()).then(_ -> runScripting()).then(_ -> finish(), error ->
		{
			print('Unexpected error: $error');
			failed++;
			finish();
		});
	}

	static function run():Promise<Dynamic>
	{
		print("\nWeb file system");

		PolymodExtended.init({
			modRoot: "mods",
			framework: Framework.CUSTOM,
			customBackend: TestBackend,
			modListFile: "web_modlist.json",
			gameLayout: "vslice"
		});

		check("uses the virtual file system", Std.isOfType(PolymodExtended.fileSystem, VirtualFileSystem));
		check("starts without mods", PolymodExtended.availableMods.length == 0);

		var fs:VirtualFileSystem = cast PolymodExtended.fileSystem;
		fs.addFolderMod("loose_mod", [
			"_polymod_meta.json" => Bytes.ofString('{"id": "loose_mod", "title": "Loose", "api_version": "0.1.0", "mod_version": "1.0.0"}'),
			"data/info.json" => Bytes.ofString('{"name": "loose"}')
		]);
		PolymodExtended.reload();
		check("loads mods from loose files", PolymodExtended.isModLoaded("loose_mod"));
		check("lists loose files", fs.readDirectoryRecursive("mods/loose_mod").contains("data/info.json"));

		fs.removeFolderMod("loose_mod");
		PolymodExtended.reload();
		check("removes loose mods", !PolymodExtended.isModLoaded("loose_mod"));

		fs.addFolderMod("songs/web_pack", [
			"_polymod_meta.json" => Bytes.ofString('{"id": "web_pack", "title": "Web Pack", "api_version": "0.1.0", "mod_version": "1.0.0"}')
		]);
		fs.addFolderMod("psych_web", [
			"_polymod_meta.json" => Bytes.ofString('{"id": "psych_web", "title": "Psych Web", "api_version": "0.1.0", "mod_version": "1.0.0"}'),
			"pack.json" => Bytes.ofString("{}"),
			"characters/gf.json" => Bytes.ofString('{"name": "gf"}')
		]);
		PolymodExtended.reload();
		check("loads mods from category folders", PolymodExtended.isModLoaded("web_pack")
			&& PolymodExtended.getModCategory("web_pack") != null && PolymodExtended.getModCategory("web_pack").id == "songs");
		check("maps folders on the web", PolymodExtended.getModLayout("psych_web") == "psych"
			&& fs.getFileContent("mods/psych_web/data/characters/gf.json") == '{"name": "gf"}');
		check("lists mapped files on the web", fs.readDirectoryRecursive("mods/psych_web").contains("data/characters/gf.json"));

		check("parses mod indexes", WebMods.parseIndex('["a.zip", {"url": "b/c.rar", "name": "c"}]', "https://example.com/mods/index.json")
			.map(entry -> entry.url).join(",") == "https://example.com/mods/a.zip,https://example.com/mods/b/c.rar");

		print("\nLoading from URLs");

		return WebMods.loadUrl('$base/mods/zip_mod.zip').then(dirName ->
		{
			check("loads zip mods from a URL", dirName == "zip_mod" && PolymodExtended.isModLoaded("zip_mod"));
			check("reads files from downloaded archives", fs.getFileContent("mods/zip_mod/data/info.json").indexOf("zip") != -1);
			return WebMods.loadIndex('$base/web/index.json');
		}).then(loaded ->
		{
			check("loads every valid mod in an index", loaded.join(",") == "rar5_mod,renamed_rar4");
			check("index mods are loaded", PolymodExtended.isModLoaded("rar5_mod") && PolymodExtended.isModLoaded("rar4_mod"));
			check("index entries can rename the mod folder", fs.isMounted("renamed_rar4"));

			var failures:Array<String> = [];
			WebMods.onLoadFailed.add(message -> failures.push(message));

			return WebMods.loadUrl('$base/mods/missing.zip').then(_ -> false, _ -> true).then(rejected ->
			{
				check("rejects missing URLs", rejected && failures.length == 1 && failures[0].indexOf("404") != -1);
				return WebMods.loadUrl('$base/mods/compressed_mod.rar').then(_ -> false, _ -> true);
			});
		}).then(rejected ->
		{
			check("rejects unreadable archives", rejected && !fs.isMounted("compressed_mod"));

			print("\nInstalled mods");
			check("detects IndexedDB", IndexedDBStore.isAvailable());

			var bytes = Bytes.ofData(js.Syntax.code("new Uint8Array(require('fs').readFileSync('fixtures/memory_mod.zip')).buffer"));
			return WebMods.installBytes(bytes, "memory_mod.zip");
		}).then(dirName ->
		{
			check("installs uploaded mods", dirName == "memory_mod" && PolymodExtended.isModLoaded("memory_mod"));
			return WebMods.listInstalled();
		}).then(installed ->
		{
			check("remembers installed mods", installed.join(",") == "memory_mod");

			fs.clearAll();
			PolymodExtended.reload();
			check("simulated page reload clears mods", !PolymodExtended.isModLoaded("memory_mod"));
			return WebMods.restoreInstalled();
		}).then(restored ->
		{
			check("restores installed mods", restored.join(",") == "memory_mod" && PolymodExtended.isModLoaded("memory_mod"));

			var blob:Dynamic = js.Syntax.code("new Blob([require('fs').readFileSync('mods/zip_mod.zip')])");
			return WebMods.installBlob(blob, "uploaded_zip.zip");
		}).then(dirName ->
		{
			check("installs from Blob/File objects", dirName == "uploaded_zip" && fs.isMounted("uploaded_zip"));
			return WebMods.uninstall("memory_mod");
		}).then(removed ->
		{
			check("uninstalls mods", removed && !PolymodExtended.isModLoaded("memory_mod"));
			return WebMods.listInstalled();
		}).then(installed ->
		{
			check("forgets uninstalled mods", installed.join(",") == "uploaded_zip");
			return WebMods.clearInstalled();
		}).then(_ -> WebMods.listInstalled()).then(installed ->
		{
			check("clears installed mods", installed.length == 0 && !fs.isMounted("uploaded_zip"));

			print("\nStorage");
			PolymodExtended.setModEnabled("zip_mod", false, true);
			var saved = Storage.read("web_modlist.json");
			check("saves the mod list without a file system", saved != null && saved.indexOf("zip_mod") != -1);
			check("disabled web mods unload", !PolymodExtended.isModLoaded("zip_mod"));
			return null;
		});
	}

	static function runDownloads():Promise<Dynamic>
	{
		print("\nDownloads");
		var events:Array<DownloadProgress> = [];

		return WebMods.loadUrl('$base/mods/rar4_mod.rar?progress', "progress_rar4", false, {onProgress: progress -> events.push(progress)}).then(dirName ->
		{
			check("reports download progress", events.length > 0 && events[events.length - 1].ratio == 1);
			var before:Int = serverState().notModified;
			return WebMods.loadUrl('$base/mods/rar5_mod.rar').then(_ -> (serverState().notModified : Int) > before);
		}).then(revalidated ->
		{
			check("reuses cached downloads when unchanged", revalidated && PolymodExtended.isModLoaded("rar5_mod"));
			return WebMods.loadUrl('$base/redirect/zip_mod.zip', "redirected_zip");
		}).then(dirName ->
		{
			check("follows redirects", dirName == "redirected_zip");
			return WebMods.loadUrl('$base/named');
		}).then(dirName ->
		{
			check("uses Content-Disposition file names", dirName == "named_mod");

			var started:WebDownload = null;
			return WebMods.loadUrl('$base/slow.zip', null, false, {
				cache: false,
				onStart: download ->
				{
					started = download;
					js.Syntax.code("setTimeout({0}, 100)", () -> download.cancel());
				}
			}).then(_ -> "", error -> Std.string(error)).then(message -> message.indexOf("cancelled") != -1 && started != null && started.cancelled);
		}).then(cancelled ->
		{
			check("cancels downloads", cancelled && WebDownload.active.length == 0);
			return WebMods.loadUrl('$base/big.zip', null, false, {maxBytes: 4096, cache: false}).then(_ -> "", error -> Std.string(error));
		}).then(message ->
		{
			check("enforces the size limit", message.indexOf("limit") != -1);
			return null;
		});
	}

	static function runSources():Promise<Dynamic>
	{
		print("\nExternal links");
		GameBananaSource.apiUrl = '$base/api';

		return WebMods.loadUrl("https://gamebanana.com/mods/123", null, true).then(dirName ->
		{
			check("installs GameBanana mods", dirName == "memory_mod" && PolymodExtended.isModLoaded("memory_mod"));
			return WebMods.getInstalledSource("memory_mod");
		}).then(source ->
		{
			check("remembers where a mod came from", source != null && source.source == "gamebanana" && source.fileId == "9001");
			return WebMods.loadUrl("https://gamebanana.com/mods/124", "bad_md5", true).then(_ -> "", error -> Std.string(error));
		}).then(message ->
		{
			check("verifies GameBanana checksums", message.indexOf("checksum") != -1);
			return WebMods.loadUrl("https://gamebanana.com/mods/123", "seven_zip", false, {fileName: "extras.7z"}).then(_ -> "", error -> Std.string(error));
		}).then(message ->
		{
			check("explains unsupported archive formats", message.indexOf(".7z") != -1);
			return WebMods.checkUpdates();
		}).then(updates ->
		{
			check("reports no update when nothing changed", updates.length == 1 && !updates[0].hasUpdate);
			serverState().gameBananaFileId = 9002;
			return WebMods.checkUpdates();
		}).then(updates ->
		{
			check("detects new GameBanana files", updates.length == 1 && updates[0].hasUpdate);
			return WebMods.updateInstalled("memory_mod");
		}).then(dirName ->
		{
			check("updates installed mods", dirName == "memory_mod");
			return WebMods.getInstalledSource("memory_mod");
		}).then(source ->
		{
			check("stores the updated source", source != null && source.fileId == "9002");
			return WebMods.loadUrl('modmanager:$base/fixtures/memory_mod.zip,Mod,123', "one_click");
		}).then(dirName ->
		{
			check("accepts 1-click links", dirName == "one_click");
			return null;
		});
	}

	static function runBackups():Promise<Dynamic>
	{
		print("\nBackups");
		var original:Bytes = null;

		return WebMods.exportInstalled("memory_mod").then(exported ->
		{
			original = exported.bytes;
			check("exports installed mods", exported.name == "memory_mod.zip" && exported.bytes.length > 0);
			return WebMods.createBackup();
		}).then(backup ->
		{
			check("creates backups", backup.length > original.length);
			return WebMods.clearInstalled().then(_ -> WebMods.restoreBackup(backup));
		}).then(restored ->
		{
			check("restores backups", restored.contains("memory_mod") && PolymodExtended.isModLoaded("memory_mod"));
			return WebMods.listInstalled();
		}).then(installed ->
		{
			check("restored mods stay installed", installed.contains("memory_mod"));
			return WebMods.restoreBackup(Bytes.ofString("nope")).then(_ -> false, _ -> true);
		}).then(rejected ->
		{
			check("rejects files that are not backups", rejected);
			return null;
		});
	}

	static function runScripting():Promise<Dynamic>
	{
		print("\nImages and scripts");

		PolymodExtended.init({modRoot: "mods", framework: Framework.CUSTOM, customBackend: TestBackend, scripts: true});
		var fs:VirtualFileSystem = cast PolymodExtended.fileSystem;
		var png = Bytes.ofHex("89504e470d0a1a0a0000000d494844520000002000000010080600000000000000");
		fs.addFolderMod("web_art", [
			"_polymod_meta.json" => Bytes.ofString('{"id": "web_art", "title": "Web Art", "api_version": "0.1.0", "mod_version": "1.0.0"}'),
			"images/icons/star.png" => png,
			"images/icons/star.txt" => Bytes.ofString("star0 = 0 0 16 16\nstar1 = 16 0 16 16"),
			"scripts/main.hx" => Bytes.ofString("var total = 0; function add(n) { total += n; return total; }")
		]);
		PolymodExtended.reload();

		check("finds images on the web", ModImages.getSource("icons/star") == "web_art" && ModImages.getInfo("icons/star").width == 32);
		check("reads atlases on the web", ModImages.getAtlas("icons/star").frames.length == 2);
		check("runs scripts on the web", ModScripts.call("add", [5]).join(",") == "5");
		return Promise.resolve(null);
	}

	static function startServer():Promise<Int>
	{
		return js.Syntax.code("require(require('path').join(process.cwd(), 'web', 'server.js')).start()");
	}

	static function serverState():Dynamic
	{
		return js.Syntax.code("require(require('path').join(process.cwd(), 'web', 'server.js')).state");
	}

	static function finish():Void
	{
		print('\nPassed: $passed, Failed: $failed');
		js.Syntax.code("process.exit({0})", failed > 0 ? 1 : 0);
	}

	static function print(text:String):Void
	{
		js.Syntax.code("console.log({0})", text);
	}

	static function check(name:String, condition:Bool):Void
	{
		if (condition)
			passed++;
		else
			failed++;

		print((condition ? "  [PASS] " : "  [FAIL] ") + name);
	}
}
