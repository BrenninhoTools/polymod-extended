package polymod.extended.sources;

import polymod.extended.sources.HttpClient.IHttpClient;
import polymod.extended.sources.ModSources;

class MediaFireSource implements IModSource
{
	public var name(default, null):String = "mediafire";

	public function new() {}

	public function canHandle(url:String):Bool
	{
		var host = ModSources.hostOf(url);
		return host == "www.mediafire.com" || host == "mediafire.com" || StringTools.endsWith(host, ".mediafire.com");
	}

	public function resolve(url:String, options:ResolveOptions, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void
	{
		var host = ModSources.hostOf(url);

		if (StringTools.startsWith(host, "download"))
		{
			onSuccess({url: url, source: name, fileName: ModSources.fileNameFromUrl(url)});
			return;
		}

		if (!StringTools.startsWith(ModSources.pathOf(url), "/file/"))
		{
			onError('"$url" is not a MediaFire file link, folders cannot be downloaded');
			return;
		}

		http.getText(url, null, page ->
		{
			var link = findDownloadLink(page);

			if (link == null)
			{
				onError("Could not find the download button on the MediaFire page, the file may have been removed");
				return;
			}

			onSuccess({url: link, source: name, fileName: ModSources.fileNameFromUrl(link), sourceId: ModSources.pathOf(url).split("/")[2]});
		}, error -> onError('Could not reach MediaFire: $error'));
	}

	public static function findDownloadLink(page:String):Null<String>
	{
		var button = ~/id="downloadButton"[^>]*href="(https?:\/\/[^"]+)"/;

		if (button.match(page))
			return StringTools.htmlUnescape(button.matched(1));

		var reversed = ~/href="(https?:\/\/download[0-9]*\.mediafire\.com\/[^"]+)"/;
		return reversed.match(page) ? StringTools.htmlUnescape(reversed.matched(1)) : null;
	}
}
