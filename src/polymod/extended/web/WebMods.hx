package polymod.extended.web;

#if js
import haxe.Json;
import haxe.io.Bytes;
import js.lib.ArrayBuffer;
import js.lib.Promise;
import polymod.extended.archive.ArchiveFormats;
import polymod.extended.fs.ArchiveMounts;
import polymod.extended.fs.VirtualFileSystem;
import polymod.extended.util.Signal;

typedef WebModEntry =
{
	url:String,
	?name:String
}

class WebMods
{
	public static final onInstalled:Signal<String> = new Signal();

	public static final onUninstalled:Signal<String> = new Signal();

	public static final onLoadFailed:Signal<String> = new Signal();

	public static var databaseName:String = "polymod-extended";

	public static var storeName:String = "mods";

	public static var autoReload:Bool = true;

	public static var fileSystem(get, never):VirtualFileSystem;

	static var store:IndexedDBStore = null;

	public static function loadUrl(url:String, ?dirName:String, install:Bool = false):Promise<String>
	{
		return loadUrlInternal(url, dirName, install, true);
	}

	public static function loadIndex(url:String, install:Bool = false):Promise<Array<String>>
	{
		return fetchText(url).then(text ->
		{
			var entries = parseIndex(text, url);
			var loaded:Array<String> = [];
			var chain:Promise<Dynamic> = Promise.resolve(null);

			for (entry in entries)
				chain = chain.then(_ -> loadUrlInternal(entry.url, entry.name, install, false).then(dirName ->
				{
					loaded.push(dirName);
					return null;
				}, _ -> null));

			return chain.then(_ ->
			{
				reload();
				return loaded;
			});
		});
	}

	static function loadUrlInternal(url:String, dirName:Null<String>, install:Bool, reloadAfter:Bool):Promise<String>
	{
		var name = fileNameFromUrl(url);

		return fetchBytes(url).then(bytes ->
		{
			if (install)
				return storeInstall(bytes, name, dirName, reloadAfter);

			var mounted = mount(bytes, name, dirName, true);

			if (mounted == null)
				return Promise.reject('"$name" is not a valid mod archive, check the error log for details');

			if (reloadAfter)
				reload();

			return Promise.resolve(mounted);
		}).catchError(error ->
		{
			var message = 'Could not load "$url": ${errorMessage(error)}';
			onLoadFailed.dispatch(message);
			return Promise.reject(message);
		});
	}

	public static function installBytes(bytes:Bytes, name:String, ?dirName:String):Promise<String>
	{
		return storeInstall(bytes, name, dirName, true);
	}

	static function storeInstall(bytes:Bytes, name:String, dirName:Null<String>, reloadAfter:Bool):Promise<String>
	{
		var target = mount(bytes, name, dirName, false);

		if (target == null)
			return Promise.reject('Could not install "$name", check the error log for details');

		var finish = (saved:Bool) ->
		{
			if (reloadAfter)
				reload();

			onInstalled.dispatch(target);
			return target;
		};

		if (!IndexedDBStore.isAvailable())
			return Promise.resolve(finish(false));

		var record = {name: name, dirName: target, data: bytes.getData(), installed: Date.now().getTime()};

		return getStore().put(target, record).then(_ -> finish(true), error ->
		{
			onLoadFailed.dispatch('Installed "$name" for this session only, it could not be saved: ${errorMessage(error)}');
			return finish(false);
		});
	}

	public static function installBlob(blob:Dynamic, ?name:String):Promise<String>
	{
		var fileName:String = name != null ? name : (blob.name != null ? blob.name : "mod.zip");
		var buffer:Promise<ArrayBuffer> = blob.arrayBuffer();
		return buffer.then(data -> installBytes(Bytes.ofData(data), fileName));
	}

	public static function restoreInstalled():Promise<Array<String>>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.resolve([]);

		var restored:Array<String> = [];

		return getStore().keys().then(keys ->
		{
			var chain:Promise<Dynamic> = Promise.resolve(null);

			for (key in keys)
				chain = chain.then(_ -> getStore().get(key)).then(record ->
				{
					if (record == null || record.data == null)
						return null;

					var dirName:String = record.dirName != null ? record.dirName : key;

					if (!fileSystem.isMounted(dirName) && mount(Bytes.ofData(record.data), record.name, dirName, false) != null)
						restored.push(dirName);

					return null;
				});

			return chain.then(_ ->
			{
				reload();
				return restored;
			});
		});
	}

	public static function uninstall(dirName:String):Promise<Bool>
	{
		var wasMounted = fileSystem.unmount(dirName);

		var removal:Promise<Bool> = IndexedDBStore.isAvailable() ? getStore().delete(dirName) : Promise.resolve(false);

		return removal.catchError(_ -> false).then(_ ->
		{
			reload();

			if (wasMounted)
				onUninstalled.dispatch(dirName);

			return wasMounted;
		});
	}

	public static function listInstalled():Promise<Array<String>>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.resolve([]);

		return getStore().keys();
	}

	public static function clearInstalled():Promise<Bool>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.resolve(false);

		return getStore().keys().then(keys ->
		{
			for (key in keys)
				fileSystem.unmount(key);

			return getStore().clear();
		}).then(result ->
		{
			reload();
			return result;
		});
	}

	public static function openFilePicker(multiple:Bool = true):Promise<Array<String>>
	{
		return new Promise<Array<Dynamic>>((resolve, reject) ->
		{
			var document:Dynamic = js.Syntax.code("(typeof globalThis.document !== 'undefined') ? globalThis.document : null");

			if (document == null)
			{
				reject("The file picker needs a browser");
				return;
			}

			var input:Dynamic = document.createElement("input");
			input.type = "file";
			input.accept = [for (format in ArchiveFormats.formats) for (extension in format.extensions) "." + extension].join(",");
			input.multiple = multiple;
			input.onchange = _ -> resolve(input.files != null ? [for (i in 0...(input.files.length : Int)) input.files[i]] : []);
			input.click();
		}).then(files -> installBlobs(files));
	}

	public static function enableDropZone(?target:Dynamic):Void->Void
	{
		var element:Dynamic = target != null ? target : js.Syntax.code("(typeof globalThis.window !== 'undefined') ? globalThis.window : null");

		if (element == null)
			return () -> {};

		var onDragOver = (event:Dynamic) -> event.preventDefault();
		var onDrop = (event:Dynamic) ->
		{
			event.preventDefault();

			var files:Dynamic = event.dataTransfer != null ? event.dataTransfer.files : null;

			if (files == null)
				return;

			var list:Array<Dynamic> = [for (i in 0...(files.length : Int)) files[i]];
			installBlobs(list.filter(file -> ArchiveFormats.isArchivePath(file.name)));
		};

		element.addEventListener("dragover", onDragOver);
		element.addEventListener("drop", onDrop);

		return () ->
		{
			element.removeEventListener("dragover", onDragOver);
			element.removeEventListener("drop", onDrop);
		};
	}

	public static function parseIndex(text:String, baseUrl:String):Array<WebModEntry>
	{
		var data:Dynamic = Json.parse(text);
		var list:Array<Dynamic> = Std.isOfType(data, Array) ? data : (data != null ? Reflect.field(data, "mods") : null);
		var result:Array<WebModEntry> = [];

		if (list == null)
			return result;

		for (item in list)
		{
			if (Std.isOfType(item, String))
				result.push({url: resolveUrl(item, baseUrl)});
			else if (item != null && Std.isOfType(Reflect.field(item, "url"), String))
				result.push({url: resolveUrl(Reflect.field(item, "url"), baseUrl), name: Reflect.field(item, "name")});
		}

		return result;
	}

	public static function resolveUrl(url:String, baseUrl:String):String
	{
		try
		{
			var location:Dynamic = js.Syntax.code("(globalThis.location != null) ? globalThis.location.href : undefined");
			var base:Dynamic = location != null ? js.Syntax.code("new URL({0}, {1})", baseUrl, location) : js.Syntax.code("new URL({0})", baseUrl);
			return js.Syntax.code("new URL({0}, {1}).href", url, base);
		}
		catch (e:Dynamic)
		{
			var slash = baseUrl.lastIndexOf("/");
			return slash == -1 ? url : baseUrl.substr(0, slash + 1) + url;
		}
	}

	static function installBlobs(files:Array<Dynamic>):Promise<Array<String>>
	{
		var installed:Array<String> = [];
		var chain:Promise<Dynamic> = Promise.resolve(null);

		for (file in files)
			chain = chain.then(_ -> installBlob(file).then(dirName -> installed.push(dirName)).catchError(error -> onLoadFailed.dispatch(errorMessage(error))));

		return chain.then(_ -> installed);
	}

	static function mount(bytes:Bytes, name:String, ?dirName:String, remember:Bool):Null<String>
	{
		var target = dirName != null ? dirName : ArchiveMounts.defaultDirName(name);

		if (fileSystem.isMounted(target))
			fileSystem.unmount(target);

		if (!fileSystem.archives.mountBytes(bytes, name, target, remember))
			return null;

		return target;
	}

	static function reload():Void
	{
		if (autoReload && PolymodExtended.initialized)
			PolymodExtended.reload();
	}

	static function fetchResponse(url:String):Promise<Dynamic>
	{
		var fetcher:Dynamic = js.Syntax.code("(typeof globalThis.fetch === 'function') ? globalThis.fetch.bind(globalThis) : null");

		if (fetcher == null)
			return Promise.reject("fetch is not available");

		var request:Promise<Dynamic> = fetcher(url);
		return request.then(response ->
		{
			if (!response.ok)
				return Promise.reject('HTTP ${response.status}');

			return Promise.resolve(response);
		});
	}

	static function fetchBytes(url:String):Promise<Bytes>
	{
		return fetchResponse(url).then(response -> (response.arrayBuffer() : Promise<ArrayBuffer>)).then(data -> Bytes.ofData(data));
	}

	static function fetchText(url:String):Promise<String>
	{
		return fetchResponse(url).then(response -> (response.text() : Promise<String>));
	}

	static function fileNameFromUrl(url:String):String
	{
		var clean = url.split("?")[0].split("#")[0];
		var slash = clean.lastIndexOf("/");
		var name = slash == -1 ? clean : clean.substr(slash + 1);

		try
		{
			name = StringTools.urlDecode(name);
		}
		catch (e:Dynamic) {}

		return name.length > 0 ? name : "mod.zip";
	}

	static function getStore():IndexedDBStore
	{
		if (store == null || store.databaseName != databaseName || store.storeName != storeName)
			store = new IndexedDBStore(databaseName, storeName);

		return store;
	}

	static function errorMessage(error:Dynamic):String
	{
		if (error == null)
			return "unknown error";

		if (Std.isOfType(error, String))
			return error;

		var message:Dynamic = Reflect.field(error, "message");
		return message != null ? Std.string(message) : Std.string(error);
	}

	static function get_fileSystem():VirtualFileSystem
	{
		var current = PolymodExtended.fileSystem;

		if (current == null || !Std.isOfType(current, VirtualFileSystem))
			throw "WebMods needs PolymodExtended.init() to run with its default web file system first";

		return cast current;
	}
}
#end
