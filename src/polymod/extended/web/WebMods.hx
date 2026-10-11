package polymod.extended.web;

#if js
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.zip.Entry;
import haxe.zip.Writer;
import js.lib.ArrayBuffer;
import js.lib.Promise;
import polymod.extended.archive.ArchiveFormats;
import polymod.extended.archive.ZipArchive;
import polymod.extended.fs.ArchiveMounts;
import polymod.extended.fs.VirtualFileSystem;
import polymod.extended.sources.ModSources;
import polymod.extended.sources.SourceRecords;
import polymod.extended.util.Signal;
import polymod.extended.web.WebDownload;

typedef WebModEntry =
{
	url:String,
	?name:String
}

typedef WebLoadOptions =
{
	?dirName:String,
	?install:Bool,
	?cache:Bool,
	?maxBytes:Int,
	?fileIndex:Int,
	?fileName:String,
	?onProgress:DownloadProgress->Void,
	?onStart:WebDownload->Void
}

typedef StorageEstimate =
{
	usage:Float,
	quota:Float,
	ratio:Float,
	persistent:Bool
}

typedef WebUpdateInfo =
{
	dirName:String,
	link:String,
	hasUpdate:Bool,
	?latest:ResolvedMod,
	?error:String
}

class WebMods
{
	public static inline final BACKUP_MANIFEST:String = "polymod-extended-backup.json";

	public static final onInstalled:Signal<String> = new Signal();

	public static final onUninstalled:Signal<String> = new Signal();

	public static final onLoadFailed:Signal<String> = new Signal();

	public static final onProgress:Signal<DownloadProgress> = new Signal();

	public static final onStorageWarning:Signal<StorageEstimate> = new Signal();

	public static var databaseName:String = "polymod-extended";

	public static var storeName:String = "mods";

	public static var autoReload:Bool = true;

	public static var cacheDownloads:Bool = true;

	public static var maxModSize:Int = 256 * 1024 * 1024;

	public static var storageWarningRatio:Float = 0.9;

	public static var fileSystem(get, never):VirtualFileSystem;

	static var store:IndexedDBStore = null;
	static var cacheStore:IndexedDBStore = null;

	public static function loadUrl(url:String, ?dirName:String, install:Bool = false, ?options:WebLoadOptions):Promise<String>
	{
		var settings = copyOptions(options);

		if (settings.dirName == null)
			settings.dirName = dirName;

		if (settings.install == null)
			settings.install = install;

		return loadInternal(url, settings, true);
	}

	public static function loadIndex(url:String, install:Bool = false, ?options:WebLoadOptions):Promise<Array<String>>
	{
		return fetchText(url).then(text ->
		{
			var entries = parseIndex(text, url);
			var loaded:Array<String> = [];
			var chain:Promise<Dynamic> = Promise.resolve(null);

			for (entry in entries)
			{
				var settings = copyOptions(options);
				settings.dirName = entry.name;
				settings.install = install;

				chain = chain.then(_ -> loadInternal(entry.url, settings, false).then(dirName ->
				{
					loaded.push(dirName);
					return null;
				}, _ -> null));
			}

			return chain.then(_ ->
			{
				reload();
				return loaded;
			});
		});
	}

	public static function resolveLink(url:String, ?options:WebLoadOptions):Promise<ResolvedMod>
	{
		return new Promise<ResolvedMod>((resolve, reject) -> ModSources.resolve(url, options != null ? {fileIndex: options.fileIndex, fileName: options.fileName} : null,
			resolve, reject));
	}

	public static function installBytes(bytes:Bytes, name:String, ?dirName:String):Promise<String>
	{
		return storeInstall(bytes, name, dirName, true, null);
	}

	public static function installBlob(blob:Dynamic, ?name:String):Promise<String>
	{
		var fileName:String = name != null ? name : (blob.name != null ? blob.name : "mod.zip");

		if (blob.size != null && (blob.size : Float) > maxModSize)
			return Promise.reject('"$fileName" is ${WebDownload.formatSize(blob.size)}, the limit is ${WebDownload.formatSize(maxModSize)}');

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

	public static function getInstalledSource(dirName:String):Promise<Null<SourceRecord>>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.resolve(null);

		return getStore().get(dirName).then(record -> record != null ? (record.source : SourceRecord) : null);
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

	public static function checkUpdates():Promise<Array<WebUpdateInfo>>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.resolve([]);

		var result:Array<WebUpdateInfo> = [];

		return getStore().keys().then(keys ->
		{
			var chain:Promise<Dynamic> = Promise.resolve(null);

			for (key in keys)
				chain = chain.then(_ -> getStore().get(key)).then(record ->
				{
					var source:SourceRecord = record != null ? record.source : null;

					if (source == null)
						return Promise.resolve(null);

					return resolveLink(source.link).then(latest ->
					{
						result.push({dirName: key, link: source.link, hasUpdate: SourceRecords.isNewer(source, latest), latest: latest});
						return null;
					}, error ->
					{
						result.push({dirName: key, link: source.link, hasUpdate: false, error: Std.string(error)});
						return null;
					});
				});

			return chain.then(_ -> result);
		});
	}

	public static function updateInstalled(dirName:String, ?options:WebLoadOptions):Promise<String>
	{
		return getInstalledSource(dirName).then(source ->
		{
			if (source == null)
				return Promise.reject('"$dirName" was not installed from a link');

			var settings = copyOptions(options);
			settings.dirName = dirName;
			settings.install = true;
			settings.cache = false;
			return loadInternal(source.link, settings, true);
		});
	}

	public static function clearCache():Promise<Bool>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.resolve(false);

		return getCacheStore().clear();
	}

	public static function getStorageEstimate():Promise<StorageEstimate>
	{
		var storage:Dynamic = js.Syntax.code("(globalThis.navigator && globalThis.navigator.storage) ? globalThis.navigator.storage : null");

		if (storage == null || storage.estimate == null)
			return Promise.resolve({usage: 0.0, quota: 0.0, ratio: 0.0, persistent: false});

		var persisted:Promise<Bool> = storage.persisted != null ? storage.persisted() : Promise.resolve(false);

		return persisted.catchError(_ -> false).then(persistent -> (storage.estimate() : Promise<Dynamic>).then(estimate ->
		{
			var usage:Float = estimate.usage != null ? estimate.usage : 0;
			var quota:Float = estimate.quota != null ? estimate.quota : 0;
			var result:StorageEstimate = {
				usage: usage,
				quota: quota,
				ratio: quota > 0 ? usage / quota : 0,
				persistent: persistent == true
			};
			return result;
		}));
	}

	public static function requestPersistentStorage():Promise<Bool>
	{
		var storage:Dynamic = js.Syntax.code("(globalThis.navigator && globalThis.navigator.storage) ? globalThis.navigator.storage : null");

		if (storage == null || storage.persist == null)
			return Promise.resolve(false);

		return (storage.persist() : Promise<Bool>).catchError(_ -> false);
	}

	public static function exportInstalled(dirName:String):Promise<{name:String, bytes:Bytes}>
	{
		if (!IndexedDBStore.isAvailable())
			return Promise.reject("Installed mods are not available in this browser");

		return getStore().get(dirName).then(record ->
		{
			if (record == null || record.data == null)
				return Promise.reject('"$dirName" is not installed');

			return Promise.resolve({name: (record.name : String), bytes: Bytes.ofData(record.data)});
		});
	}

	public static function createBackup():Promise<Bytes>
	{
		var entries:List<Entry> = new List();
		var manifest:Dynamic = {version: 1, created: Date.now().getTime(), mods: []};
		var chain:Promise<Dynamic> = Promise.resolve(null);

		var keys:Promise<Array<String>> = IndexedDBStore.isAvailable() ? getStore().keys() : Promise.resolve([]);

		return keys.then(list ->
		{
			for (key in list)
				chain = chain.then(_ -> getStore().get(key)).then(record ->
				{
					if (record == null || record.data == null)
						return null;

					var fileName = 'mods/${StringTools.replace(key, "/", "__")}.${haxe.io.Path.extension(record.name).toLowerCase()}';
					entries.add(entry(fileName, Bytes.ofData(record.data)));
					(manifest.mods : Array<Dynamic>).push({dirName: key, name: record.name, file: fileName, source: record.source});
					return null;
				});

			return chain.then(_ ->
			{
				entries.add(entry("modlist.json", Bytes.ofString(PolymodExtended.modList.toJson(true))));
				entries.add(entry("settings.json", Bytes.ofString(PolymodExtended.settings.toJson(true))));
				entries.add(entry(BACKUP_MANIFEST, Bytes.ofString(Json.stringify(manifest, null, "\t"))));

				var output = new BytesOutput();
				new Writer(output).write(entries);
				return output.getBytes();
			});
		});
	}

	public static function restoreBackup(bytes:Bytes):Promise<Array<String>>
	{
		var archive:ZipArchive;
		var manifest:Dynamic;

		try
		{
			archive = new ZipArchive(new polymod.extended.archive.ArchiveSource.BytesArchiveSource(bytes), "backup.zip");
			manifest = Json.parse(archive.read(BACKUP_MANIFEST).toString());
		}
		catch (e:Dynamic)
		{
			return Promise.reject("This file is not a polymod-extended backup");
		}

		var restored:Array<String> = [];
		var chain:Promise<Dynamic> = Promise.resolve(null);
		var mods:Array<Dynamic> = manifest.mods != null ? manifest.mods : [];

		for (item in mods)
			chain = chain.then(_ ->
			{
				var data = archive.read(item.file);

				if (data == null)
					return null;

				return storeInstall(data, item.name, item.dirName, false, item.source).then(dirName ->
				{
					restored.push(dirName);
					return null;
				}, _ -> null);
			});

		return chain.then(_ ->
		{
			if (archive.has("modlist.json"))
				PolymodExtended.setModList(polymod.extended.ModList.fromJson(archive.read("modlist.json").toString()));

			if (archive.has("settings.json"))
				restoreSettings(archive.read("settings.json").toString());

			reload();
			return restored;
		});
	}

	public static function saveFile(bytes:Bytes, name:String):Bool
	{
		var document:Dynamic = js.Syntax.code("(typeof globalThis.document !== 'undefined') ? globalThis.document : null");

		if (document == null)
			return false;

		var blob:Dynamic = js.Syntax.code("new Blob([{0}], {type: 'application/octet-stream'})", bytes.getData());
		var url:String = js.Syntax.code("URL.createObjectURL({0})", blob);
		var link:Dynamic = document.createElement("a");
		link.href = url;
		link.download = name;
		document.body.appendChild(link);
		link.click();
		document.body.removeChild(link);
		js.Syntax.code("setTimeout(() => URL.revokeObjectURL({0}), 1000)", url);
		return true;
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

			var transfer:Dynamic = event.dataTransfer;

			if (transfer == null)
				return;

			var files:Dynamic = transfer.files;
			var list:Array<Dynamic> = files != null ? [for (i in 0...(files.length : Int)) files[i]] : [];
			var archives = list.filter(file -> ArchiveFormats.isArchivePath(file.name));

			if (archives.length > 0)
			{
				installBlobs(archives);
				return;
			}

			var text:String = transfer.getData != null ? transfer.getData("text/uri-list") : null;

			if (text == null || text.length == 0)
				text = transfer.getData != null ? transfer.getData("text/plain") : null;

			if (text != null && StringTools.trim(text).length > 0)
				loadUrl(StringTools.trim(text.split("\n")[0]), null, true).catchError(_ -> null);
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
		if (ModSources.parseOneClick(url) != null && !StringTools.startsWith(url, "http"))
			return url;

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

	static function loadInternal(link:String, options:WebLoadOptions, reloadAfter:Bool):Promise<String>
	{
		var useCache = options.cache != null ? options.cache : cacheDownloads;
		var limit = options.maxBytes != null ? options.maxBytes : maxModSize;

		return resolveLink(link, options).then(resolved ->
		{
			if (resolved.size != null && resolved.size > limit)
				return Promise.reject('the mod is ${WebDownload.formatSize(resolved.size)}, the limit is ${WebDownload.formatSize(limit)}');

			return readCache(useCache ? resolved.url : null).then(cached ->
			{
				var download = new WebDownload(ModSources.proxied(resolved.url), {
					maxBytes: limit,
					etag: cached != null ? cached.etag : null,
					lastModified: cached != null ? cached.lastModified : null
				});

				download.onProgress.add(progress ->
				{
					onProgress.dispatch(progress);

					if (options.onProgress != null)
						options.onProgress(progress);
				});

				if (options.onStart != null)
					options.onStart(download);

				return download.promise.then(response ->
				{
					var bytes = response.notModified && cached != null ? Bytes.ofData(cached.data) : response.bytes;

					if (bytes == null)
						return Promise.reject("the server returned no data");

					var fileName = resolved.fileName != null ? resolved.fileName : (response.fileName != null ? response.fileName : ModSources.fileNameFromUrl(resolved.url));
					var unsupported = ModSources.unsupportedArchiveMessage(fileName);

					if (unsupported != null)
						return Promise.reject(unsupported);

					if (haxe.io.Path.extension(fileName).length == 0)
						fileName += ".zip";

					if (resolved.md5 != null && haxe.crypto.Md5.make(bytes).toHex().toLowerCase() != resolved.md5.toLowerCase())
						return Promise.reject("the downloaded file is corrupted (checksum mismatch)");

					var source = new SourceRecords().set("mod", link, resolved, response.etag, response.lastModified);
					var write:Promise<Dynamic> = useCache && !response.notModified ? writeCache(resolved.url, fileName, bytes, response) : Promise.resolve(null);

					return write.then(_ ->
					{
						if (options.install == true)
							return storeInstall(bytes, fileName, options.dirName, reloadAfter, source);

						var mounted = mount(bytes, fileName, options.dirName, true);

						if (mounted == null)
							return Promise.reject('"$fileName" is not a valid mod archive, check the error log for details');

						if (reloadAfter)
							reload();

						return Promise.resolve(mounted);
					});
				}, error ->
				{
					if (cached != null && !download.cancelled)
					{
						var mounted = mount(Bytes.ofData(cached.data), cached.name, options.dirName, true);

						if (mounted != null)
						{
							if (reloadAfter)
								reload();

							return Promise.resolve(mounted);
						}
					}

					return Promise.reject(error);
				});
			});
		}).catchError(error ->
		{
			var message = 'Could not load "$link": ${errorMessage(error)}';
			onLoadFailed.dispatch(message);
			return Promise.reject(message);
		});
	}

	static function storeInstall(bytes:Bytes, name:String, dirName:Null<String>, reloadAfter:Bool, source:Null<SourceRecord>):Promise<String>
	{
		if (bytes.length > maxModSize)
			return Promise.reject('"$name" is ${WebDownload.formatSize(bytes.length)}, the limit is ${WebDownload.formatSize(maxModSize)}');

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

		return getStorageEstimate().then(estimate ->
		{
			if (estimate.quota > 0 && estimate.usage + bytes.length > estimate.quota)
				return Promise.reject('There is not enough browser storage to keep "$name" (${WebDownload.formatSize(bytes.length)} needed)');

			var record = {
				name: name,
				dirName: target,
				data: bytes.getData(),
				size: bytes.length,
				installed: Date.now().getTime(),
				source: source
			};

			return getStore().put(target, record).then(_ ->
			{
				checkStorage();
				return finish(true);
			});
		}).catchError(error ->
		{
			onLoadFailed.dispatch('Installed "$name" for this session only, it could not be saved: ${errorMessage(error)}');
			return finish(false);
		});
	}

	static function checkStorage():Void
	{
		getStorageEstimate().then(estimate ->
		{
			if (estimate.quota > 0 && estimate.ratio >= storageWarningRatio)
				onStorageWarning.dispatch(estimate);

			return null;
		});
	}

	static function readCache(url:Null<String>):Promise<Dynamic>
	{
		if (url == null || !IndexedDBStore.isAvailable())
			return Promise.resolve(null);

		return getCacheStore().get(url).catchError(_ -> null);
	}

	static function writeCache(url:String, name:String, bytes:Bytes, response:DownloadResponse):Promise<Dynamic>
	{
		if (!IndexedDBStore.isAvailable() || (response.etag == null && response.lastModified == null))
			return Promise.resolve(null);

		return getCacheStore().put(url, {
			name: name,
			data: bytes.getData(),
			etag: response.etag,
			lastModified: response.lastModified,
			cached: Date.now().getTime()
		}).catchError(_ -> null);
	}

	static function restoreSettings(json:String):Void
	{
		var restored = polymod.extended.ModSettings.fromJson(json);

		for (mod in PolymodExtended.availableMods)
			for (setting in PolymodExtended.settings.getDefinitions(mod.id))
			{
				restored.define(mod.id, PolymodExtended.settings.getDefinitions(mod.id));
				var value = restored.get(mod.id, setting.id);

				if (value != null)
					PolymodExtended.setSetting(mod.id, setting.id, value);
			}
	}

	static function entry(fileName:String, data:Bytes):Entry
	{
		return {
			fileName: fileName,
			fileSize: data.length,
			fileTime: Date.now(),
			compressed: false,
			dataSize: data.length,
			data: data,
			crc32: haxe.crypto.Crc32.make(data)
		};
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

	static function fetchText(url:String):Promise<String>
	{
		return new Promise<String>((resolve, reject) -> polymod.extended.sources.HttpClient.current.getText(url, null, resolve, reject));
	}

	static function copyOptions(options:Null<WebLoadOptions>):WebLoadOptions
	{
		if (options == null)
			return {};

		return {
			dirName: options.dirName,
			install: options.install,
			cache: options.cache,
			maxBytes: options.maxBytes,
			fileIndex: options.fileIndex,
			fileName: options.fileName,
			onProgress: options.onProgress,
			onStart: options.onStart
		};
	}

	static function getStore():IndexedDBStore
	{
		if (store == null || store.databaseName != databaseName || store.storeName != storeName)
			store = new IndexedDBStore(databaseName, storeName);

		return store;
	}

	static function getCacheStore():IndexedDBStore
	{
		var name = databaseName + "-cache";

		if (cacheStore == null || cacheStore.databaseName != name)
			cacheStore = new IndexedDBStore(name, "downloads");

		return cacheStore;
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
