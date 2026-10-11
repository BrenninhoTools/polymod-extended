package polymod.extended.structure;

import polymod.extended.structure.FolderMapper.FolderMapping;

class FolderLayouts
{
	public static final PSYCH:String = "psych";
	public static final VSLICE:String = "vslice";
	public static final CODENAME:String = "codename";

	public static var layouts:Map<String, Map<String, String>> = [
		PSYCH => [
			"characters" => "characters",
			"stages" => "stages",
			"weeks" => "weeks",
			"songAudio" => "songs/*"
		],
		VSLICE => [
			"characters" => "data/characters",
			"stages" => "data/stages",
			"weeks" => "data/levels",
			"songAudio" => "songs/*"
		],
		CODENAME => [
			"characters" => "data/characters",
			"stages" => "data/stages",
			"weeks" => "data/weeks/weeks",
			"songAudio" => "songs/*/song"
		]
	];

	public static function normalizeName(name:String):Null<String>
	{
		if (name == null)
			return null;

		return switch (name.toLowerCase())
		{
			case "psych", "psych-engine", "psychengine": PSYCH;
			case "vslice", "v-slice", "base", "basegame", "funkin": VSLICE;
			case "codename", "codename-engine", "codenameengine": CODENAME;
			default: name.toLowerCase();
		}
	}

	public static function register(name:String, folders:Map<String, String>):Void
	{
		layouts.set(normalizeName(name), folders);
	}

	public static function mappings(from:String, to:String):Array<FolderMapping>
	{
		var source = layouts.get(normalizeName(from));
		var target = layouts.get(normalizeName(to));
		var result:Array<FolderMapping> = [];

		if (source == null || target == null || normalizeName(from) == normalizeName(to))
			return result;

		for (concept => sourcePath in source)
		{
			var targetPath = target.get(concept);

			if (targetPath != null && targetPath != sourcePath)
				result.push({from: sourcePath, to: targetPath});
		}

		result.sort((a, b) -> a.to < b.to ? -1 : (a.to > b.to ? 1 : 0));
		return result;
	}

	public static function detect(files:Array<String>):Null<String>
	{
		var scores:Map<String, Int> = [PSYCH => 0, VSLICE => 0, CODENAME => 0];

		for (raw in files)
		{
			var file = StringTools.replace(raw, "\\", "/").toLowerCase();

			if (file == "pack.json" || StringTools.startsWith(file, "custom_notetypes/") || StringTools.startsWith(file, "custom_events/"))
				scores.set(PSYCH, scores.get(PSYCH) + 3);
			else if (StringTools.startsWith(file, "weeks/") || (StringTools.startsWith(file, "characters/") && StringTools.endsWith(file, ".json")))
				scores.set(PSYCH, scores.get(PSYCH) + 1);

			if (StringTools.startsWith(file, "data/levels/") || StringTools.startsWith(file, "_merge/") || StringTools.startsWith(file, "_append/")
				|| StringTools.endsWith(file, ".hxc"))
				scores.set(VSLICE, scores.get(VSLICE) + 3);
			else if (StringTools.startsWith(file, "data/songs/") || StringTools.startsWith(file, "data/notestyles/"))
				scores.set(VSLICE, scores.get(VSLICE) + 2);

			if (StringTools.startsWith(file, "data/weeks/weeks/") || ~/^songs\/[^\/]+\/song\//.match(file))
				scores.set(CODENAME, scores.get(CODENAME) + 3);
			else if (StringTools.startsWith(file, "data/characters/") && StringTools.endsWith(file, ".xml"))
				scores.set(CODENAME, scores.get(CODENAME) + 2);
		}

		var best:Null<String> = null;
		var bestScore = 0;

		for (name in [PSYCH, VSLICE, CODENAME])
			if (scores.get(name) > bestScore)
			{
				best = name;
				bestScore = scores.get(name);
			}

		return best;
	}
}
