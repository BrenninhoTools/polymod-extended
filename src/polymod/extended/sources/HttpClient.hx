package polymod.extended.sources;

interface IHttpClient
{
	public function getText(url:String, headers:Map<String, String>, onSuccess:String->Void, onError:String->Void):Void;
}

class HttpClient
{
	public static var userAgent:String = "polymod-extended";

	public static var current:IHttpClient = createDefault();

	public static function createDefault():IHttpClient
	{
		#if js
		return new FetchHttpClient();
		#elseif sys
		return new SysHttpClient();
		#else
		return new UnavailableHttpClient();
		#end
	}
}

class UnavailableHttpClient implements IHttpClient
{
	public function new() {}

	public function getText(url:String, headers:Map<String, String>, onSuccess:String->Void, onError:String->Void):Void
	{
		onError("HTTP requests are not available on this target");
	}
}

class MockHttpClient implements IHttpClient
{
	public var responses:Map<String, String> = [];

	public var requests(default, null):Array<String> = [];

	public function new(?responses:Map<String, String>)
	{
		if (responses != null)
			this.responses = responses;
	}

	public function getText(url:String, headers:Map<String, String>, onSuccess:String->Void, onError:String->Void):Void
	{
		requests.push(url);

		if (responses.exists(url))
			onSuccess(responses.get(url));
		else
			onError('HTTP 404');
	}
}

#if sys
class SysHttpClient implements IHttpClient
{
	public function new() {}

	public function getText(url:String, headers:Map<String, String>, onSuccess:String->Void, onError:String->Void):Void
	{
		var current = url;

		for (attempt in 0...9)
		{
			var http = new haxe.Http(current);
			var failed:Null<String> = null;
			var status = 0;
			var result:Null<String> = null;

			http.setHeader("User-Agent", HttpClient.userAgent);

			if (headers != null)
				for (name => value in headers)
					http.setHeader(name, value);

			http.onStatus = code -> status = code;
			http.onError = message -> failed = message;
			http.onData = data -> result = data;

			try
			{
				http.request(false);
			}
			catch (e:Dynamic)
			{
				failed = Std.string(e);
			}

			var location:Null<String> = null;

			if (http.responseHeaders != null)
				for (key => value in http.responseHeaders)
					if (key.toLowerCase() == "location")
						location = value;

			if (status >= 300 && status < 400 && location != null)
			{
				current = polymod.extended.desktop.RemoteMods.resolveLocation(current, location);
				continue;
			}

			if (status >= 400)
				onError('HTTP $status');
			else if (failed != null)
				onError(failed);
			else
				onSuccess(result != null ? result : "");

			return;
		}

		onError("Too many redirects");
	}
}
#end

#if js
class FetchHttpClient implements IHttpClient
{
	public function new() {}

	public function getText(url:String, headers:Map<String, String>, onSuccess:String->Void, onError:String->Void):Void
	{
		var fetcher:Dynamic = js.Syntax.code("(typeof globalThis.fetch === 'function') ? globalThis.fetch.bind(globalThis) : null");

		if (fetcher == null)
		{
			onError("fetch is not available");
			return;
		}

		var init:Dynamic = {headers: {}};

		if (headers != null)
			for (name => value in headers)
				Reflect.setField(init.headers, name, value);

		var request:js.lib.Promise<Dynamic> = fetcher(ModSources.proxied(url), init);

		request.then(response ->
		{
			if (!response.ok)
			{
				onError('HTTP ${response.status}');
				return null;
			}

			return (response.text() : js.lib.Promise<String>).then(text ->
			{
				onSuccess(text);
				return null;
			});
		}).catchError(error -> onError(Std.string(error)));
	}
}
#end
