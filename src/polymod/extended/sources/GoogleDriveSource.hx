package polymod.extended.sources;

import polymod.extended.sources.HttpClient.IHttpClient;
import polymod.extended.sources.ModSources;

class GoogleDriveSource implements IModSource
{
	public var name(default, null):String = "googledrive";

	public function new() {}

	public function canHandle(url:String):Bool
	{
		var host = ModSources.hostOf(url);
		return host == "drive.google.com" || host == "docs.google.com" || host == "drive.usercontent.google.com";
	}

	public function resolve(url:String, options:ResolveOptions, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void
	{
		var id = fileId(url);

		if (id == null)
		{
			onError('"$url" is not a Google Drive file link, folders cannot be downloaded');
			return;
		}

		onSuccess({
			url: 'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t',
			source: name,
			sourceId: id
		});
	}

	public static function fileId(url:String):Null<String>
	{
		var path = ~/\/file\/d\/([A-Za-z0-9_-]+)/;

		if (path.match(url))
			return path.matched(1);

		var id = ModSources.queryValue(url, "id");
		return id != null && ~/^[A-Za-z0-9_-]+$/.match(id) ? id : null;
	}
}
