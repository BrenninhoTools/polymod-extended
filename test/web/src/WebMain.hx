package;

import haxe.io.Bytes;
import js.lib.Promise;
import polymod.Polymod.Framework;
import polymod.extended.PolymodExtended;
import polymod.extended.fs.VirtualFileSystem;
import polymod.extended.util.Storage;
import polymod.extended.web.IndexedDBStore;
import polymod.extended.web.WebMods;

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
		}).then(_ -> finish(), error ->
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
			modListFile: "web_modlist.json"
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

	static function startServer():Promise<Int>
	{
		return new Promise<Int>((resolve, reject) ->
		{
			var server:Dynamic = js.Syntax.code("require('http').createServer((request, response) => {
				const path = require('path');
				const file = path.join(process.cwd(), decodeURIComponent(request.url.split('?')[0]));
				require('fs').readFile(file, (error, data) => {
					if (error) { response.writeHead(404); response.end('not found'); return; }
					response.writeHead(200);
					response.end(data);
				});
			})");
			server.listen(0, "127.0.0.1", () -> resolve(server.address().port));
			server.unref();
		});
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
