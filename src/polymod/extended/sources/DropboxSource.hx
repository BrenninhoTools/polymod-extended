package polymod.extended.sources;

import polymod.extended.sources.HttpClient.IHttpClient;
import polymod.extended.sources.ModSources;

class DropboxSource implements IModSource
{
	public var name(default, null):String = "dropbox";

	public function new() {}

	public function canHandle(url:String):Bool
	{
		var host = ModSources.hostOf(url);
		return host == "www.dropbox.com" || host == "dropbox.com" || host == "dl.dropboxusercontent.com";
	}

	public function resolve(url:String, options:ResolveOptions, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void
	{
		if (ModSources.hostOf(url) == "dl.dropboxusercontent.com")
		{
			onSuccess({url: url, source: name, fileName: ModSources.fileNameFromUrl(url)});
			return;
		}

		var path = ModSources.pathOf(url);

		if (!StringTools.startsWith(path, "/s/") && !StringTools.startsWith(path, "/scl/fi/"))
		{
			onError('"$url" is not a Dropbox file link');
			return;
		}

		onSuccess({url: directUrl(url), source: name, fileName: ModSources.fileNameFromUrl(url)});
	}

	public static function directUrl(url:String):String
	{
		var hash = url.indexOf("#");
		var clean = hash == -1 ? url : url.substr(0, hash);
		var question = clean.indexOf("?");

		if (question == -1)
			return clean + "?dl=1";

		var base = clean.substr(0, question);
		var pairs = clean.substr(question + 1).split("&").filter(pair -> pair.length > 0 && !StringTools.startsWith(pair, "dl=") && !StringTools.startsWith(pair, "raw="));
		pairs.push("dl=1");
		return base + "?" + pairs.join("&");
	}
}
