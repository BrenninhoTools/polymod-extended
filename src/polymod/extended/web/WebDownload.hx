package polymod.extended.web;

#if js
import haxe.io.Bytes;
import js.lib.Promise;
import js.lib.Uint8Array;
import polymod.extended.util.Signal;

typedef DownloadProgress =
{
	url:String,
	loaded:Int,
	total:Null<Int>,
	ratio:Float
}

typedef DownloadResponse =
{
	bytes:Null<Bytes>,
	status:Int,
	notModified:Bool,
	etag:Null<String>,
	lastModified:Null<String>,
	fileName:Null<String>,
	finalUrl:String
}

typedef DownloadOptions =
{
	?maxBytes:Int,
	?headers:Dynamic,
	?etag:String,
	?lastModified:String
}

class WebDownload
{
	public static var active(default, null):Array<WebDownload> = [];

	public final onProgress:Signal<DownloadProgress> = new Signal();

	public var url(default, null):String;

	public var loaded(default, null):Int = 0;

	public var total(default, null):Null<Int> = null;

	public var cancelled(default, null):Bool = false;

	public var finished(default, null):Bool = false;

	public var promise(default, null):Promise<DownloadResponse>;

	var controller:Dynamic = null;
	var options:DownloadOptions;

	public function new(url:String, ?options:DownloadOptions)
	{
		this.url = url;
		this.options = options != null ? options : {};
		active.push(this);
		promise = start();
	}

	public static function cancelAll():Void
	{
		for (download in active.copy())
			download.cancel();
	}

	public function cancel():Void
	{
		if (finished || cancelled)
			return;

		cancelled = true;

		if (controller != null)
			controller.abort();
	}

	function abort():Void
	{
		if (controller != null)
			controller.abort();
	}

	public function getProgress():DownloadProgress
	{
		return {
			url: url,
			loaded: loaded,
			total: total,
			ratio: total != null && total > 0 ? Math.min(1, loaded / total) : -1
		};
	}

	function start():Promise<DownloadResponse>
	{
		var fetcher:Dynamic = js.Syntax.code("(typeof globalThis.fetch === 'function') ? globalThis.fetch.bind(globalThis) : null");

		if (fetcher == null)
			return finish(Promise.reject("fetch is not available"));

		controller = js.Syntax.code("(typeof globalThis.AbortController === 'function') ? new globalThis.AbortController() : null");

		var headers:Dynamic = {};

		if (options.headers != null)
			for (field in Reflect.fields(options.headers))
				Reflect.setField(headers, field, Reflect.field(options.headers, field));

		if (options.etag != null)
			Reflect.setField(headers, "If-None-Match", options.etag);

		if (options.lastModified != null)
			Reflect.setField(headers, "If-Modified-Since", options.lastModified);

		var init:Dynamic = {headers: headers};

		if (controller != null)
			init.signal = controller.signal;

		var request:Promise<Dynamic> = fetcher(url, init);

		return finish(request.then(response ->
		{
			var status:Int = response.status;
			var info:DownloadResponse = {
				bytes: null,
				status: status,
				notModified: status == 304,
				etag: header(response, "ETag"),
				lastModified: header(response, "Last-Modified"),
				fileName: fileNameFromDisposition(header(response, "Content-Disposition")),
				finalUrl: response.url != null && (response.url : String).length > 0 ? response.url : url
			};

			if (status == 304)
				return Promise.resolve(info);

			if (!response.ok)
				return Promise.reject('HTTP $status');

			var length = header(response, "Content-Length");
			total = length != null ? Std.parseInt(length) : null;

			if (options.maxBytes != null && total != null && total > options.maxBytes)
			{
				abort();
				return Promise.reject('the mod is ${formatSize(total)}, the limit is ${formatSize(options.maxBytes)}');
			}

			return readBody(response).then(bytes ->
			{
				info.bytes = bytes;
				return info;
			});
		}));
	}

	function readBody(response:Dynamic):Promise<Bytes>
	{
		if (response.body == null || response.body.getReader == null)
			return (response.arrayBuffer() : Promise<js.lib.ArrayBuffer>).then(data ->
			{
				loaded = data.byteLength;
				emitProgress();
				return checkLimit(Bytes.ofData(data));
			});

		var reader:Dynamic = response.body.getReader();
		var chunks:Array<Uint8Array> = [];

		return new Promise<Bytes>((resolve, reject) ->
		{
			function pump():Void
			{
				(reader.read() : Promise<Dynamic>).then(result ->
				{
					if (result.done)
					{
						var output = new Uint8Array(loaded);
						var offset = 0;

						for (chunk in chunks)
						{
							output.set(chunk, offset);
							offset += chunk.length;
						}

						resolve(Bytes.ofData(output.buffer));
						return;
					}

					var chunk:Uint8Array = result.value;
					chunks.push(chunk);
					loaded += chunk.length;

					if (options.maxBytes != null && loaded > options.maxBytes)
					{
						abort();
						reject('the mod is larger than the ${formatSize(options.maxBytes)} limit');
						return;
					}

					emitProgress();
					pump();
				}, reject);
			}

			pump();
		});
	}

	function checkLimit(bytes:Bytes):Bytes
	{
		if (options.maxBytes != null && bytes.length > options.maxBytes)
			throw 'the mod is ${formatSize(bytes.length)}, the limit is ${formatSize(options.maxBytes)}';

		return bytes;
	}

	function finish<T>(promise:Promise<T>):Promise<T>
	{
		return promise.then(value ->
		{
			finished = true;
			active.remove(this);
			return value;
		}, error ->
		{
			finished = true;
			active.remove(this);
			return Promise.reject(cancelled ? "the download was cancelled" : error);
		});
	}

	function emitProgress():Void
	{
		onProgress.dispatch(getProgress());
	}

	static function header(response:Dynamic, name:String):Null<String>
	{
		try
		{
			var value:Dynamic = response.headers.get(name);
			return value != null ? Std.string(value) : null;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function fileNameFromDisposition(value:Null<String>):Null<String>
	{
		if (value == null)
			return null;

		var encoded = ~/filename\*\s*=\s*(?:UTF-8'')?([^;]+)/i;

		if (encoded.match(value))
		{
			try
			{
				return StringTools.urlDecode(StringTools.trim(encoded.matched(1)).split('"').join(""));
			}
			catch (e:Dynamic) {}
		}

		var plain = ~/filename\s*=\s*"?([^";]+)"?/i;
		return plain.match(value) ? StringTools.trim(plain.matched(1)) : null;
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
#end
