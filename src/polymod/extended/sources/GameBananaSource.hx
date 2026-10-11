package polymod.extended.sources;

import haxe.Json;
import polymod.extended.sources.HttpClient.IHttpClient;
import polymod.extended.sources.ModSources;

class GameBananaSource implements IModSource
{
	public static var apiUrl:String = "https://gamebanana.com/apiv11";

	public static var models:Map<String, String> = ["mods" => "Mod", "sounds" => "Sound", "wips" => "Wip", "tools" => "Tool"];

	public var name(default, null):String = "gamebanana";

	public function new() {}

	public function canHandle(url:String):Bool
	{
		var host = ModSources.hostOf(url);
		return host == "gamebanana.com" || host == "www.gamebanana.com" || host == "files.gamebanana.com";
	}

	public function resolve(url:String, options:ResolveOptions, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void
	{
		var path = ModSources.pathOf(url);
		var direct = ~/^\/(dl|mmdl)\/(\d+)/;
		var isDirect = direct.match(path);
		var isFileHost = ModSources.hostOf(url) == "files.gamebanana.com";

		if (isDirect || isFileHost)
		{
			onSuccess({
				url: url,
				source: name,
				fileId: isDirect ? direct.matched(2) : null,
				fileName: isFileHost ? ModSources.fileNameFromUrl(url) : null
			});
			return;
		}

		var item = ~/^\/([a-z]+)\/(\d+)/i;

		if (!item.match(path) || !models.exists(item.matched(1).toLowerCase()))
		{
			onError('"$url" is not a GameBanana mod page');
			return;
		}

		var model = models.get(item.matched(1).toLowerCase());
		var id = item.matched(2);

		http.getText('$apiUrl/$model/$id/ProfilePage', null, text ->
		{
			var result = parseProfile(text, model, id, options);

			if (result.error != null)
				onError(result.error);
			else
				onSuccess(result.mod);
		}, error -> onError('Could not reach GameBanana: $error'));
	}

	public static function parseProfile(text:String, model:String, id:String, options:ResolveOptions):{?mod:ResolvedMod, ?error:String}
	{
		var data:Dynamic;

		try
		{
			data = Json.parse(text);
		}
		catch (e:Dynamic)
		{
			return {error: "GameBanana returned an invalid response"};
		}

		var rawFiles:Dynamic = Reflect.field(data, "_aFiles");
		var files:Array<RemoteFile> = [];

		if (Std.isOfType(rawFiles, Array))
			for (item in (rawFiles : Array<Dynamic>))
			{
				if (item == null || Reflect.field(item, "_bIsArchived") == true)
					continue;

				var antivirus:Dynamic = Reflect.field(item, "_sAvResult");

				if (antivirus != null && antivirus != "clean" && antivirus != "")
					continue;

				var downloadUrl:Dynamic = Reflect.field(item, "_sDownloadUrl");
				var fileName:Dynamic = Reflect.field(item, "_sFile");

				if (!Std.isOfType(downloadUrl, String) || !Std.isOfType(fileName, String))
					continue;

				var md5:Dynamic = Reflect.field(item, "_sMd5Checksum");
				var size:Dynamic = Reflect.field(item, "_nFilesize");
				var version:Dynamic = Reflect.field(item, "_sVersion");
				var description:Dynamic = Reflect.field(item, "_sDescription");

				files.push({
					url: downloadUrl,
					fileName: fileName,
					id: Std.string(Reflect.field(item, "_idRow")),
					size: Std.isOfType(size, Int) ? size : null,
					md5: Std.isOfType(md5, String) && (md5 : String).length == 32 ? md5 : null,
					version: Std.isOfType(version, String) && (version : String).length > 0 ? version : null,
					description: Std.isOfType(description, String) ? description : null
				});
			}

		if (files.length == 0)
			return {error: 'GameBanana $model $id has no downloadable files'};

		var file = ModSources.pickFile(files, options);

		if (file == null)
			return {error: 'The requested file was not found on GameBanana $model $id'};

		var unsupported = ModSources.unsupportedArchiveMessage(file.fileName);

		if (unsupported != null)
			return {error: unsupported};

		var title:Dynamic = Reflect.field(data, "_sName");
		var version:Dynamic = Reflect.field(data, "_sVersion");
		var updated:Dynamic = Reflect.field(data, "_tsDateUpdated");
		var modified:Dynamic = Reflect.field(data, "_tsDateModified");

		return {
			mod: {
				url: file.url,
				source: "gamebanana",
				fileName: file.fileName,
				title: Std.isOfType(title, String) ? title : null,
				version: file.version != null ? file.version : (Std.isOfType(version, String) && (version : String).length > 0 ? version : null),
				size: file.size,
				md5: file.md5,
				sourceId: '$model/$id',
				fileId: file.id,
				updatedAt: Std.isOfType(updated, Int) || Std.isOfType(updated, Float) ? updated : (Std.isOfType(modified, Int) ? modified : null),
				files: files
			}
		};
	}
}
