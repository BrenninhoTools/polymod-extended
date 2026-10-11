package polymod.extended.sources;

import haxe.io.Path;
import polymod.extended.archive.ArchiveFormats;
import polymod.extended.sources.HttpClient.IHttpClient;

typedef RemoteFile =
{
	url:String,
	fileName:String,
	?id:String,
	?size:Int,
	?md5:String,
	?version:String,
	?description:String
}

typedef ResolvedMod =
{
	url:String,
	source:String,
	?fileName:String,
	?title:String,
	?version:String,
	?size:Int,
	?md5:String,
	?sourceId:String,
	?fileId:String,
	?updatedAt:Float,
	?files:Array<RemoteFile>
}

typedef ResolveOptions =
{
	?fileIndex:Int,
	?fileName:String
}

typedef OneClickLink =
{
	url:String,
	?scheme:String,
	?itemType:String,
	?itemId:String,
	?extension:String
}

interface IModSource
{
	public var name(default, null):String;

	public function canHandle(url:String):Bool;

	public function resolve(url:String, options:ResolveOptions, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void;
}

class ModSources
{
	public static var sources(default, null):Array<IModSource> = [
		new GameBananaSource(),
		new GitHubSource(),
		new GoogleDriveSource(),
		new DropboxSource(),
		new MediaFireSource()
	];

	public static var corsProxy:Null<String> = null;

	public static var proxyAll:Bool = false;

	public static var proxyHosts:Array<String> = [
		"gamebanana.com",
		"files.gamebanana.com",
		"drive.google.com",
		"drive.usercontent.google.com",
		"www.dropbox.com",
		"dl.dropboxusercontent.com",
		"www.mediafire.com",
		"download.mediafire.com",
		"objects.githubusercontent.com",
		"release-assets.githubusercontent.com",
		"github.com"
	];

	public static function register(source:IModSource):Void
	{
		unregister(source.name);
		sources.unshift(source);
	}

	public static function unregister(name:String):Void
	{
		sources = sources.filter(source -> source.name != name);
	}

	public static function getSource(url:String):Null<IModSource>
	{
		var link = normalizeLink(url);

		for (source in sources)
			if (source.canHandle(link))
				return source;

		return null;
	}

	public static function resolve(url:String, ?options:ResolveOptions, onSuccess:ResolvedMod->Void, onError:String->Void, ?http:IHttpClient):Void
	{
		var link = normalizeLink(url);

		if (link == null || !(StringTools.startsWith(link, "https://") || StringTools.startsWith(link, "http://")))
		{
			onError('"$url" is not a web link');
			return;
		}

		var source = getSource(link);
		var client = http != null ? http : HttpClient.current;

		if (source == null)
		{
			var name = fileNameFromUrl(link);
			onSuccess({url: link, source: "direct", fileName: Path.extension(name).length > 0 ? name : null});
			return;
		}

		try
		{
			source.resolve(link, options != null ? options : {}, client, onSuccess, onError);
		}
		catch (e:Dynamic)
		{
			onError(Std.string(e));
		}
	}

	public static function parseOneClick(uri:String):Null<OneClickLink>
	{
		if (uri == null)
			return null;

		var text = StringTools.trim(uri);
		var start = text.indexOf("http");

		if (start == -1)
			return null;

		var scheme = start > 0 ? text.substr(0, start).split(":")[0] : null;
		var parts = text.substr(start).split(",");
		var url = parts[0];

		if (!StringTools.startsWith(url, "https://") && !StringTools.startsWith(url, "http://"))
			return null;

		return {
			url: url,
			scheme: scheme != null && scheme.length > 0 ? scheme : null,
			itemType: parts.length > 1 ? parts[1] : null,
			itemId: parts.length > 2 ? parts[2] : null,
			extension: parts.length > 3 ? parts[3] : null
		};
	}

	public static function normalizeLink(url:String):Null<String>
	{
		if (url == null)
			return null;

		var text = StringTools.trim(url);
		var oneClick = parseOneClick(text);

		if (oneClick != null && !StringTools.startsWith(text, "http"))
			return oneClick.url;

		return text;
	}

	public static function proxied(url:String):String
	{
		if (corsProxy == null || corsProxy.length == 0 || StringTools.startsWith(url, corsProxy))
			return url;

		if (!proxyAll && !proxyHosts.contains(hostOf(url)))
			return url;

		return corsProxy.indexOf("{url}") != -1 ? StringTools.replace(corsProxy, "{url}", StringTools.urlEncode(url)) : corsProxy + StringTools.urlEncode(url);
	}

	public static function hostOf(url:String):String
	{
		var match = ~/^[a-z]+:\/\/([^\/?#:]+)/i;
		return match.match(url) ? match.matched(1).toLowerCase() : "";
	}

	public static function pathOf(url:String):String
	{
		var match = ~/^[a-z]+:\/\/[^\/?#]+([^?#]*)/i;
		return match.match(url) ? match.matched(1) : "";
	}

	public static function queryValue(url:String, key:String):Null<String>
	{
		var question = url.indexOf("?");

		if (question == -1)
			return null;

		for (pair in url.substr(question + 1).split("#")[0].split("&"))
		{
			var equals = pair.indexOf("=");

			if (equals != -1 && pair.substr(0, equals) == key)
				return pair.substr(equals + 1);
		}

		return null;
	}

	public static function fileNameFromUrl(url:String):String
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

	public static function pickFile(files:Array<RemoteFile>, options:ResolveOptions):Null<RemoteFile>
	{
		if (files.length == 0)
			return null;

		if (options.fileName != null)
		{
			for (file in files)
				if (file.fileName.toLowerCase() == options.fileName.toLowerCase())
					return file;

			return null;
		}

		if (options.fileIndex != null)
			return options.fileIndex >= 0 && options.fileIndex < files.length ? files[options.fileIndex] : null;

		for (file in files)
			if (ArchiveFormats.isArchivePath(file.fileName))
				return file;

		return files[0];
	}

	public static function unsupportedArchiveMessage(fileName:String):Null<String>
	{
		if (fileName == null || ArchiveFormats.isArchivePath(fileName))
			return null;

		var extension = Path.extension(fileName).toLowerCase();

		if (extension.length == 0)
			return null;

		return '"$fileName" is a .$extension file, only ${[for (format in ArchiveFormats.formats) for (ext in format.extensions) "." + ext].join(" and ")} mods can be installed';
	}
}
