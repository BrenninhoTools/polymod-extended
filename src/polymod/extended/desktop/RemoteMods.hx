package polymod.extended.desktop;

#if sys
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.extended.desktop.DesktopMods.InstallOptions;
import polymod.extended.sources.ModSources;
import polymod.extended.sources.SourceRecords;
import polymod.extended.util.Signal;

typedef RemoteProgress =
{
	link:String,
	loaded:Int,
	total:Null<Int>,
	ratio:Float
}

typedef RemoteInstallOptions =
{
	?category:String,
	?replace:Bool,
	?reload:Bool,
	?enable:Bool,
	?fileIndex:Int,
	?fileName:String,
	?maxBytes:Int
}

typedef RemoteInstallResult =
{
	success:Bool,
	?id:String,
	?path:String,
	?mod:ResolvedMod,
	?error:String
}

class RemoteMods
{
	public static final onProgress:Signal<RemoteProgress> = new Signal();

	public static var maxModSize:Int = 512 * 1024 * 1024;

	public static var recordsFile:String = ".sources.json";

	public static var downloadFolder:String = ".downloads";

	public static var busy(default, null):Bool = false;

	static var cancelRequested:Bool = false;

	#if target.threaded
	static var mutex:sys.thread.Mutex = new sys.thread.Mutex();
	static var mainThread:sys.thread.Thread = sys.thread.Thread.current();
	static var pending:Array<Void->Void> = [];
	#end

	public static function resolve(link:String, ?options:RemoteInstallOptions):{?mod:ResolvedMod, ?error:String}
	{
		var result:{?mod:ResolvedMod, ?error:String} = {error: "The link could not be resolved"};
		ModSources.resolve(link, options != null ? {fileIndex: options.fileIndex, fileName: options.fileName} : null, mod -> result = {mod: mod},
			error -> result = {error: error});
		return result;
	}

	public static function install(link:String, ?options:RemoteInstallOptions):RemoteInstallResult
	{
		if (options == null)
			options = {};

		if (busy)
			return {success: false, error: "Another mod is already downloading"};

		busy = true;
		cancelRequested = false;

		var result = installInternal(link, options);
		busy = false;
		return result;
	}

	public static function installAsync(link:String, ?options:RemoteInstallOptions, ?onDone:RemoteInstallResult->Void):Void
	{
		#if target.threaded
		if (busy)
		{
			if (onDone != null)
				onDone({success: false, error: "Another mod is already downloading"});

			return;
		}

		busy = true;
		cancelRequested = false;

		var settings = options != null ? options : {};
		var reload = settings.reload != false;
		settings.reload = false;

		sys.thread.Thread.create(() ->
		{
			var result = installInternal(link, settings, false);

			queue(() ->
			{
				busy = false;

				if (result.success)
				{
					if (reload && PolymodExtended.initialized)
						PolymodExtended.reload();

					DesktopMods.onInstalled.dispatch(result.id);
				}

				if (onDone != null)
					onDone(result);
			});
		});
		#else
		var result = install(link, options);

		if (onDone != null)
			onDone(result);
		#end
	}

	public static function cancel():Void
	{
		if (busy)
			cancelRequested = true;
	}

	public static function update():Void
	{
		#if target.threaded
		mutex.acquire();
		var callbacks = pending;
		pending = [];
		mutex.release();

		for (callback in callbacks)
			callback();
		#end
	}

	public static function getSource(id:String):Null<SourceRecord>
	{
		return loadRecords().get(id);
	}

	public static function getRecords():SourceRecords
	{
		return loadRecords();
	}

	public static function checkUpdates(?ids:Array<String>):Array<UpdateInfo>
	{
		var records = loadRecords();
		var result:Array<UpdateInfo> = [];

		for (id in (ids != null ? ids : records.ids()))
		{
			var record = records.get(id);

			if (record == null || PolymodExtended.getMod(id) == null)
				continue;

			var resolved = resolve(record.link);

			if (resolved.error != null)
			{
				result.push({id: id, record: record, hasUpdate: false, error: resolved.error});
				continue;
			}

			result.push({id: id, record: record, latest: resolved.mod, hasUpdate: SourceRecords.isNewer(record, resolved.mod)});
		}

		return result;
	}

	public static function updateMod(id:String, ?options:RemoteInstallOptions):RemoteInstallResult
	{
		var record = getSource(id);

		if (record == null)
			return {success: false, error: 'Mod "$id" was not installed from a link'};

		var settings = options != null ? options : {};
		settings.replace = true;

		var category = PolymodExtended.getModCategory(id);

		if (settings.category == null && category != null && category.folder)
			settings.category = category.id;

		return install(record.link, settings);
	}

	static function installInternal(link:String, options:RemoteInstallOptions, reload:Bool = true):RemoteInstallResult
	{
		var resolved = resolve(link, options);

		if (resolved.error != null)
			return {success: false, error: resolved.error};

		var mod = resolved.mod;
		var limit = options.maxBytes != null ? options.maxBytes : maxModSize;

		if (mod.size != null && mod.size > limit)
			return {success: false, mod: mod, error: 'The mod is ${formatSize(mod.size)}, the limit is ${formatSize(limit)}'};

		var folder = Path.join([modRoot(), downloadFolder]);
		var partFile = Path.join([folder, "download_" + Std.int(Date.now().getTime()) + ".part"]);
		var download:{?fileName:String, ?error:String};

		try
		{
			if (!sys.FileSystem.exists(folder))
				sys.FileSystem.createDirectory(folder);

			download = downloadTo(mod.url, partFile, limit, link);
		}
		catch (e:Dynamic)
		{
			download = {error: Std.string(e)};
		}

		if (download.error != null)
		{
			deleteQuietly(partFile);
			return {success: false, mod: mod, error: download.error};
		}

		var fileName = mod.fileName != null ? mod.fileName : (download.fileName != null ? download.fileName : ModSources.fileNameFromUrl(mod.url));
		var unsupported = ModSources.unsupportedArchiveMessage(fileName);

		if (unsupported != null)
		{
			deleteQuietly(partFile);
			return {success: false, mod: mod, error: unsupported};
		}

		if (Path.extension(fileName).length == 0)
			fileName += ".zip";

		if (mod.md5 != null)
		{
			var actual = haxe.crypto.Md5.make(sys.io.File.getBytes(partFile)).toHex();

			if (actual.toLowerCase() != mod.md5.toLowerCase())
			{
				deleteQuietly(partFile);
				return {success: false, mod: mod, error: "The downloaded file is corrupted (checksum mismatch), try again"};
			}
		}

		var archiveFile = Path.join([folder, Path.withoutDirectory(fileName)]);
		deleteQuietly(archiveFile);
		sys.FileSystem.rename(partFile, archiveFile);

		var installed = DesktopMods.installMod(archiveFile, {
			category: options.category,
			replace: options.replace,
			enable: options.enable,
			reload: reload && options.reload != false
		});

		deleteQuietly(archiveFile);
		removeFolderIfEmpty(folder);

		if (!installed.success)
			return {success: false, mod: mod, error: installed.error};

		var records = loadRecords();
		records.set(installed.id, link, mod);
		saveRecords(records);

		return {success: true, id: installed.id, path: installed.path, mod: mod};
	}

	static function downloadTo(url:String, file:String, limit:Int, link:String, redirects:Int = 0):{?fileName:String, ?error:String}
	{
		if (redirects > 8)
			return {error: "Too many redirects"};

		var http = new haxe.Http(url);
		var output = sys.io.File.write(file, true);
		var progress = new ProgressOutput(output, limit, link);
		var failed:Null<String> = null;
		var status = 0;
		var location:Null<String> = null;

		http.setHeader("User-Agent", polymod.extended.sources.HttpClient.userAgent);
		http.onStatus = code ->
		{
			status = code;
			location = header(http, "Location");

			if (code >= 300 && code < 400 && location != null)
			{
				progress.discard = true;
				return;
			}

			var length = header(http, "Content-Length");
			progress.total = length != null ? Std.parseInt(length) : null;
		};
		http.onError = message -> failed = message;

		try
		{
			http.customRequest(false, progress);
		}
		catch (e:Dynamic)
		{
			failed = progress.failure != null ? progress.failure : Std.string(e);
		}

		try
		{
			output.close();
		}
		catch (e:Dynamic) {}

		if (progress.failure != null)
			return {error: progress.failure};

		if (status >= 300 && status < 400 && location != null)
			return downloadTo(resolveLocation(url, location), file, limit, link, redirects + 1);

		if (status >= 400)
			return {error: 'HTTP $status'};

		if (failed != null)
			return {error: failed};

		return {fileName: fileNameFromDisposition(header(http, "Content-Disposition"))};
	}

	public static function resolveLocation(base:String, location:String):String
	{
		if (StringTools.startsWith(location, "http://") || StringTools.startsWith(location, "https://"))
			return location;

		var origin = ~/^([a-z]+:\/\/[^\/]+)/i;

		if (!origin.match(base))
			return location;

		if (StringTools.startsWith(location, "//"))
			return base.split(":")[0] + ":" + location;

		if (StringTools.startsWith(location, "/"))
			return origin.matched(1) + location;

		var clean = base.split("?")[0];
		return clean.substr(0, clean.lastIndexOf("/") + 1) + location;
	}

	static function header(http:haxe.Http, name:String):Null<String>
	{
		if (http.responseHeaders == null)
			return null;

		for (key => value in http.responseHeaders)
			if (key.toLowerCase() == name.toLowerCase())
				return value;

		return null;
	}

	static function queue(callback:Void->Void):Void
	{
		#if target.threaded
		if (sys.thread.Thread.current() == mainThread)
		{
			callback();
			return;
		}

		mutex.acquire();
		pending.push(callback);
		mutex.release();
		#else
		callback();
		#end
	}

	static function loadRecords():SourceRecords
	{
		var path = Path.join([modRoot(), recordsFile]);
		return SourceRecords.fromJson(sys.FileSystem.exists(path) ? sys.io.File.getContent(path) : null);
	}

	static function saveRecords(records:SourceRecords):Void
	{
		try
		{
			sys.io.File.saveContent(Path.join([modRoot(), recordsFile]), records.toJson());
		}
		catch (e:Dynamic) {}
	}

	@:allow(polymod.extended.desktop.DesktopMods)
	static function forget(id:String):Void
	{
		var records = loadRecords();

		if (records.remove(id))
			saveRecords(records);
	}

	@:allow(polymod.extended.desktop.ProgressOutput)
	static function isCancelled():Bool
	{
		return cancelRequested;
	}

	@:allow(polymod.extended.desktop.ProgressOutput)
	static function reportProgress(progress:RemoteProgress):Void
	{
		queue(() -> onProgress.dispatch(progress));
	}

	static function modRoot():String
	{
		return DesktopMods.modRoot;
	}

	static function deleteQuietly(path:String):Void
	{
		try
		{
			if (sys.FileSystem.exists(path))
				sys.FileSystem.deleteFile(path);
		}
		catch (e:Dynamic) {}
	}

	static function removeFolderIfEmpty(path:String):Void
	{
		try
		{
			if (sys.FileSystem.exists(path) && sys.FileSystem.readDirectory(path).length == 0)
				sys.FileSystem.deleteDirectory(path);
		}
		catch (e:Dynamic) {}
	}

	public static function fileNameFromDisposition(value:Null<String>):Null<String>
	{
		if (value == null)
			return null;

		var encoded = ~/filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i;

		if (encoded.match(value))
		{
			try
			{
				return Path.withoutDirectory(StringTools.urlDecode(StringTools.trim(encoded.matched(1)).split('"').join("")));
			}
			catch (e:Dynamic) {}
		}

		var plain = ~/filename\s*=\s*"?([^";]+)"?/i;
		return plain.match(value) ? Path.withoutDirectory(StringTools.trim(plain.matched(1))) : null;
	}

	public static function formatSize(bytes:Float):String
	{
		if (bytes < 1024)
			return '${Std.int(bytes)} B';

		if (bytes < 1024 * 1024)
			return '${Math.round(bytes / 102.4) / 10} KB';

		return '${Math.round(bytes / (1024 * 102.4)) / 10} MB';
	}
}

class ProgressOutput extends haxe.io.Output
{
	public var total:Null<Int> = null;

	public var discard:Bool = false;

	public var loaded(default, null):Int = 0;

	public var failure(default, null):Null<String> = null;

	var target:haxe.io.Output;
	var limit:Int;
	var link:String;
	var lastReport:Float = 0;

	public function new(target:haxe.io.Output, limit:Int, link:String)
	{
		this.target = target;
		this.limit = limit;
		this.link = link;
	}

	override public function writeByte(c:Int):Void
	{
		if (discard)
			return;

		check(1);
		target.writeByte(c);
		advance(1);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int
	{
		if (discard)
			return len;

		check(len);
		var written = target.writeBytes(s, pos, len);
		advance(written);
		return written;
	}

	function check(count:Int):Void
	{
		if (RemoteMods.isCancelled())
			fail("The download was cancelled");

		if (loaded + count > limit)
			fail('The mod is larger than the ${RemoteMods.formatSize(limit)} limit');
	}

	function advance(count:Int):Void
	{
		loaded += count;
		var now = haxe.Timer.stamp();

		if (now - lastReport >= 0.1 || (total != null && loaded >= total))
		{
			lastReport = now;
			RemoteMods.reportProgress({
				link: link,
				loaded: loaded,
				total: total,
				ratio: total != null && total > 0 ? Math.min(1, loaded / total) : -1
			});
		}
	}

	function fail(message:String):Void
	{
		failure = message;
		throw message;
	}
}
#end
