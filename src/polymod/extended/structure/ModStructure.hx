package polymod.extended.structure;

import haxe.Json;
import haxe.io.Path;

typedef FolderRule =
{
	path:String,
	?extensions:Array<String>,
	?required:Bool,
	?template:Bool,
	?description:String
}

enum abstract StructureIssueKind(String) from String to String
{
	var LOOSE_FILE = "loose_file";
	var UNKNOWN_FOLDER = "unknown_folder";
	var WRONG_EXTENSION = "wrong_extension";
	var MISSING_FOLDER = "missing_folder";
	var MISSING_ROOT_FILE = "missing_root_file";
}

typedef StructureIssue =
{
	kind:StructureIssueKind,
	path:String,
	message:String,
	?suggestion:String,
	?recommended:Bool
}

class ModStructure
{
	public static final ATLAS_EXTENSIONS:Array<String> = ["xml", "txt", "json"];

	public static final IMAGE_EXTENSIONS:Array<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "astc", "ktx", "ktx2"];

	public static final AUDIO_EXTENSIONS:Array<String> = ["ogg", "wav", "mp3", "flac"];

	public var name:String;

	public var folders:Array<FolderRule>;

	public var rootFiles:Array<String>;

	public var requiredRootFiles:Array<String> = [];

	public var recommendedRootFiles:Array<String> = [];

	public var ignoredFolders:Array<String> = ["_append", "_merge", ".git", ".github", ".vscode"];

	public var wrapperFolders:Array<String> = ["assets"];

	public var allowUnknownFolders:Bool = false;

	public var extensionTargets:Map<String, String> = [];

	public var songAudioFolder:Null<String> = "songs";

	public function new(name:String, folders:Array<FolderRule>, ?rootFiles:Array<String>)
	{
		this.name = name;
		this.folders = folders;
		this.rootFiles = rootFiles != null ? rootFiles : defaultRootFiles();

		for (folder in folders)
			if (folder.extensions != null && folder.path.indexOf("/") == -1)
				for (extension in folder.extensions)
					if (!extensionTargets.exists(extension.toLowerCase()) && !ATLAS_EXTENSIONS.contains(extension.toLowerCase()))
						extensionTargets.set(extension.toLowerCase(), folder.path);

		var dataFolder = hasFolder("data") ? "data" : null;

		if (dataFolder != null)
			for (extension in ATLAS_EXTENSIONS)
				if (!extensionTargets.exists(extension))
					extensionTargets.set(extension, dataFolder);

		if (hasFolder("sounds"))
			for (extension in AUDIO_EXTENSIONS)
				extensionTargets.set(extension, "sounds");

		if (!hasFolder("songs"))
			songAudioFolder = null;
	}

	public function hasFolder(path:String):Bool
	{
		return getRule(path) != null;
	}

	public function getRule(path:String):Null<FolderRule>
	{
		for (folder in folders)
			if (folder.path == path)
				return folder;

		return null;
	}

	public function findRule(directory:String):Null<FolderRule>
	{
		var best:Null<FolderRule> = null;

		for (folder in folders)
			if ((directory == folder.path || StringTools.startsWith(directory, folder.path + "/"))
				&& (best == null || folder.path.length > best.path.length))
				best = folder;

		return best;
	}

	public function getTemplateFolders():Array<String>
	{
		var result = [for (folder in folders) if (folder.required == true || folder.template == true) folder.path];
		return result.length > 0 ? result : [for (folder in folders) if (folder.path.indexOf("/") == -1) folder.path];
	}

	public function isRootFileAllowed(name:String):Bool
	{
		for (pattern in rootFiles)
			if (matchesPattern(name, pattern))
				return true;

		return false;
	}

	public function targetFolderFor(file:String):Null<String>
	{
		var extension = Path.extension(file).toLowerCase();
		return extensionTargets.get(extension);
	}

	public function validate(files:Array<String>):Array<StructureIssue>
	{
		var issues:Array<StructureIssue> = [];
		var reportedFolders:Array<String> = [];
		var normalized = [for (file in files) normalizePath(file)].filter(file -> file.length > 0);

		for (file in normalized)
		{
			var first = file.split("/")[0];

			if (ignoredFolders.contains(first))
				continue;

			var directory = Path.directory(file);

			if (directory.length == 0)
			{
				if (!isRootFileAllowed(file))
					issues.push({
						kind: LOOSE_FILE,
						path: file,
						message: '"$file" should not be in the root of the mod',
						suggestion: suggest(file, normalized)
					});

				continue;
			}

			var rule = findRule(directory);

			if (rule == null)
			{
				if (allowUnknownFolders)
					continue;

				if (!reportedFolders.contains(first))
				{
					reportedFolders.push(first);
					issues.push({kind: UNKNOWN_FOLDER, path: first, message: 'Unknown folder "$first"'});
				}

				issues.push({
					kind: UNKNOWN_FOLDER,
					path: file,
					message: '"$file" is inside an unknown folder',
					suggestion: suggest(file, normalized)
				});
				continue;
			}

			var extension = Path.extension(file).toLowerCase();

			if (rule.extensions != null && rule.extensions.length > 0 && !rule.extensions.contains(extension))
				issues.push({
					kind: WRONG_EXTENSION,
					path: file,
					message: '".$extension" files do not belong in "${rule.path}"',
					suggestion: suggest(file, normalized)
				});
		}

		var lowerFiles = [for (file in normalized) file.toLowerCase()];

		for (name in requiredRootFiles)
			if (!lowerFiles.contains(name.toLowerCase()))
				issues.push({kind: MISSING_ROOT_FILE, path: name, message: 'Required file "$name" is missing from the root of the mod'});

		for (name in recommendedRootFiles)
			if (!lowerFiles.contains(name.toLowerCase()))
				issues.push({kind: MISSING_ROOT_FILE, path: name, message: 'The mod has no "$name"', recommended: true});

		for (folder in folders)
			if (folder.required == true && !hasAnyFile(normalized, folder.path))
				issues.push({kind: MISSING_FOLDER, path: folder.path, message: 'Required folder "${folder.path}" is missing or empty'});

		return issues;
	}

	public function suggest(file:String, ?allFiles:Array<String>):Null<String>
	{
		var path = normalizePath(file);
		var parts = path.split("/");

		if (parts.length > 1 && wrapperFolders.contains(parts[0].toLowerCase()))
		{
			var rest = parts.slice(1).join("/");
			var directory = Path.directory(rest);

			if (directory.length > 0 && findRule(directory) != null)
				return rest;
		}

		var name = parts[parts.length - 1];
		var base = Path.withoutExtension(name);
		var extension = Path.extension(name).toLowerCase();
		var directory = Path.directory(path);
		var inner = parts.length > 1 ? parts.slice(1).join("/") : name;

		if (ATLAS_EXTENSIONS.contains(extension) && allFiles != null)
			for (other in allFiles)
				if (other != path && Path.directory(other) == directory && Path.withoutExtension(Path.withoutDirectory(other)) == base
					&& IMAGE_EXTENSIONS.contains(Path.extension(other).toLowerCase()))
				{
					var imageTarget = targetFolderFor(other);
					var inImageFolder = directory.length > 0 && findRule(directory) != null && findRule(directory).path == imageTarget;
					return inImageFolder ? null : (imageTarget != null ? imageTarget + "/" + inner : null);
				}

		if (songAudioFolder != null && AUDIO_EXTENSIONS.contains(extension) && ~/^(inst|voices)([-_].*)?$/i.match(base))
		{
			var parent = parts.length >= 3 ? parts[parts.length - 2] : (parts.length == 2 && findRule(parts[0]) == null ? parts[0] : null);
			return parent != null ? '$songAudioFolder/$parent/$name' : '$songAudioFolder/$name';
		}

		var target = targetFolderFor(name);
		return target != null ? target + "/" + inner : null;
	}

	public function toJson(pretty:Bool = true):String
	{
		return Json.stringify({
			name: name,
			folders: folders,
			rootFiles: rootFiles,
			ignoredFolders: ignoredFolders,
			requiredRootFiles: requiredRootFiles,
			recommendedRootFiles: recommendedRootFiles,
			allowUnknownFolders: allowUnknownFolders
		}, null, pretty ? "\t" : null);
	}

	public static function fromJson(text:String):ModStructure
	{
		var data:Dynamic = Json.parse(text);
		var folders:Array<FolderRule> = [];
		var rawFolders:Dynamic = Reflect.field(data, "folders");

		if (Std.isOfType(rawFolders, Array))
			for (item in (rawFolders : Array<Dynamic>))
			{
				if (Std.isOfType(item, String))
					folders.push({path: normalizePath(item)});
				else if (item != null && Std.isOfType(Reflect.field(item, "path"), String))
					folders.push({
						path: normalizePath(Reflect.field(item, "path")),
						extensions: readStrings(Reflect.field(item, "extensions")),
						required: Reflect.field(item, "required") == true,
						template: Reflect.field(item, "template") == true,
						description: Reflect.field(item, "description")
					});
			}

		var name:Dynamic = Reflect.field(data, "name");
		var structure = new ModStructure(Std.isOfType(name, String) ? name : "custom", folders, readStrings(Reflect.field(data, "rootFiles")));
		var ignored = readStrings(Reflect.field(data, "ignoredFolders"));

		if (ignored != null)
			structure.ignoredFolders = ignored;

		structure.allowUnknownFolders = Reflect.field(data, "allowUnknownFolders") == true;

		var required = readNames(Reflect.field(data, "requiredRootFiles"));
		var recommended = readNames(Reflect.field(data, "recommendedRootFiles"));

		if (required != null)
			structure.requiredRootFiles = required;

		if (recommended != null)
			structure.recommendedRootFiles = recommended;
		return structure;
	}

	public static function defaultRootFiles():Array<String>
	{
		return [
			"_polymod_meta.json",
			"_polymod_icon.png",
			"_category.json",
			"pack.json",
			"pack.png",
			"readme*",
			"license*",
			"credits*",
			"changelog*",
			"*.md"
		];
	}

	static function hasAnyFile(files:Array<String>, folder:String):Bool
	{
		for (file in files)
			if (StringTools.startsWith(file, folder + "/"))
				return true;

		return false;
	}

	static function matchesPattern(name:String, pattern:String):Bool
	{
		var lowerName = name.toLowerCase();
		var lowerPattern = pattern.toLowerCase();

		if (lowerPattern.indexOf("*") == -1)
			return lowerName == lowerPattern;

		var parts = lowerPattern.split("*");
		var position = 0;

		for (i in 0...parts.length)
		{
			var part = parts[i];

			if (part.length == 0)
				continue;

			var found = lowerName.indexOf(part, position);

			if (found == -1 || (i == 0 && found != 0))
				return false;

			position = found + part.length;
		}

		var last = parts[parts.length - 1];
		return last.length == 0 || StringTools.endsWith(lowerName, last);
	}

	static function readNames(value:Dynamic):Null<Array<String>>
	{
		if (!Std.isOfType(value, Array))
			return null;

		return [for (item in (value : Array<Dynamic>)) if (Std.isOfType(item, String)) (item : String)];
	}

	static function readStrings(value:Dynamic):Null<Array<String>>
	{
		if (!Std.isOfType(value, Array))
			return null;

		return [for (item in (value : Array<Dynamic>)) if (Std.isOfType(item, String)) (item : String).toLowerCase()];
	}

	public static function normalizePath(path:String):String
	{
		return [for (part in StringTools.replace(path, "\\", "/").split("/")) if (part != "" && part != ".") part].join("/");
	}
}
