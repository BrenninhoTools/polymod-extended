package polymod.extended.sources;

import haxe.Json;
import polymod.extended.archive.ArchiveFormats;
import polymod.extended.sources.HttpClient.IHttpClient;
import polymod.extended.sources.ModSources;

class GitHubSource implements IModSource
{
	public static var apiUrl:String = "https://api.github.com";

	public var name(default, null):String = "github";

	public function new() {}

	public function canHandle(url:String):Bool
	{
		var host = ModSources.hostOf(url);
		return host == "github.com" || host == "www.github.com" || host == "codeload.github.com";
	}

	public function resolve(url:String, options:ResolveOptions, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void
	{
		if (ModSources.hostOf(url) == "codeload.github.com")
		{
			onSuccess({url: url, source: name, fileName: ModSources.fileNameFromUrl(url)});
			return;
		}

		var parts = ModSources.pathOf(url).split("/").filter(part -> part.length > 0);

		if (parts.length < 2)
		{
			onError('"$url" is not a GitHub repository link');
			return;
		}

		var owner = parts[0];
		var repo = StringTools.endsWith(parts[1], ".git") ? parts[1].substr(0, parts[1].length - 4) : parts[1];
		var rest = parts.slice(2);
		var sourceId = '$owner/$repo';

		if (rest.length >= 4 && rest[0] == "releases" && rest[1] == "download")
		{
			onSuccess({url: url, source: name, sourceId: sourceId, version: rest[2], fileName: ModSources.fileNameFromUrl(url)});
			return;
		}

		if (rest.length >= 1 && rest[0] == "archive")
		{
			onSuccess({url: url, source: name, sourceId: sourceId, fileName: '$repo-${ModSources.fileNameFromUrl(url)}'});
			return;
		}

		if (rest.length >= 2 && rest[0] == "tree")
		{
			var branch = rest.slice(1).join("/");
			onSuccess(branchZip(owner, repo, branch));
			return;
		}

		var releasePath = rest.length >= 3 && rest[0] == "releases" && rest[1] == "tag" ? 'releases/tags/${rest[2]}' : "releases/latest";

		http.getText('$apiUrl/repos/$owner/$repo/$releasePath', ["Accept" => "application/vnd.github+json"], text ->
		{
			var result = parseRelease(text, sourceId, options);

			if (result != null)
			{
				onSuccess(result);
				return;
			}

			if (releasePath != "releases/latest")
			{
				onError('Release "${rest[2]}" of $sourceId has no .zip or .rar files');
				return;
			}

			resolveDefaultBranch(owner, repo, http, onSuccess, onError);
		}, error ->
		{
			if (releasePath != "releases/latest")
				onError('Could not find release "${rest[2]}" of $sourceId: $error');
			else
				resolveDefaultBranch(owner, repo, http, onSuccess, onError);
		});
	}

	public static function parseRelease(text:String, sourceId:String, options:ResolveOptions):Null<ResolvedMod>
	{
		var data:Dynamic;

		try
		{
			data = Json.parse(text);
		}
		catch (e:Dynamic)
		{
			return null;
		}

		var assets:Dynamic = Reflect.field(data, "assets");
		var files:Array<RemoteFile> = [];

		if (Std.isOfType(assets, Array))
			for (asset in (assets : Array<Dynamic>))
			{
				var url:Dynamic = Reflect.field(asset, "browser_download_url");
				var fileName:Dynamic = Reflect.field(asset, "name");
				var size:Dynamic = Reflect.field(asset, "size");

				if (Std.isOfType(url, String) && Std.isOfType(fileName, String) && ArchiveFormats.isArchivePath(fileName))
					files.push({url: url, fileName: fileName, size: Std.isOfType(size, Int) ? size : null, id: Std.string(Reflect.field(asset, "id"))});
			}

		var file = ModSources.pickFile(files, options);

		if (file == null)
			return null;

		var tag:Dynamic = Reflect.field(data, "tag_name");
		var title:Dynamic = Reflect.field(data, "name");
		var published:Dynamic = Reflect.field(data, "published_at");

		return {
			url: file.url,
			source: "github",
			fileName: file.fileName,
			title: Std.isOfType(title, String) && (title : String).length > 0 ? title : sourceId,
			version: Std.isOfType(tag, String) ? tag : null,
			size: file.size,
			sourceId: sourceId,
			fileId: file.id,
			updatedAt: Std.isOfType(published, String) ? parseDate(published) : null,
			files: files
		};
	}

	static function resolveDefaultBranch(owner:String, repo:String, http:IHttpClient, onSuccess:ResolvedMod->Void, onError:String->Void):Void
	{
		http.getText('$apiUrl/repos/$owner/$repo', ["Accept" => "application/vnd.github+json"], text ->
		{
			var branch = "main";

			try
			{
				var data:Dynamic = Json.parse(text);
				var value:Dynamic = Reflect.field(data, "default_branch");

				if (Std.isOfType(value, String))
					branch = value;
			}
			catch (e:Dynamic) {}

			onSuccess(branchZip(owner, repo, branch));
		}, error -> onError('Could not find the GitHub repository $owner/$repo: $error'));
	}

	static function branchZip(owner:String, repo:String, branch:String):ResolvedMod
	{
		return {
			url: 'https://codeload.github.com/$owner/$repo/zip/refs/heads/$branch',
			source: "github",
			fileName: '$repo-$branch.zip',
			title: '$owner/$repo',
			version: branch,
			sourceId: '$owner/$repo'
		};
	}

	static function parseDate(value:String):Null<Float>
	{
		try
		{
			var clean = StringTools.replace(StringTools.replace(value, "T", " "), "Z", "");
			return Date.fromString(clean.substr(0, 19)).getTime() / 1000;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}
}
