package polymod.extended.structure;

typedef FolderMapping =
{
	from:String,
	to:String
}

interface IFolderMapping
{
	public var mapper(default, null):FolderMapper;
}

private typedef CompiledMapping =
{
	from:Array<String>,
	to:Array<String>
}

class FolderMapper
{
	var mods:Map<String, Array<CompiledMapping>> = [];
	var bases:Array<String> = [];

	public function new() {}

	public function set(modPath:String, mappings:Array<FolderMapping>):Array<String>
	{
		var errors:Array<String> = [];
		var base = normalize(modPath);
		var compiled:Array<CompiledMapping> = [];

		for (mapping in mappings)
		{
			if (mapping == null || mapping.from == null || mapping.to == null)
				continue;

			var from = split(mapping.from);
			var to = split(mapping.to);

			if (from.length == 0 || to.length == 0 || from.contains("..") || to.contains(".."))
			{
				errors.push('invalid folder mapping "${mapping.from}" -> "${mapping.to}"');
				continue;
			}

			if (wildcards(from) != wildcards(to))
			{
				errors.push('folder mapping "${mapping.from}" -> "${mapping.to}" must use the same number of "*" on both sides');
				continue;
			}

			if (from.join("/") != to.join("/"))
				compiled.push({from: from, to: to});
		}

		remove(modPath);

		if (compiled.length > 0)
		{
			mods.set(base, compiled);
			bases.push(base);
			bases.sort((a, b) -> b.length - a.length);
		}

		return errors;
	}

	public function remove(modPath:String):Void
	{
		var base = normalize(modPath);
		mods.remove(base);
		bases.remove(base);
	}

	public function clear():Void
	{
		mods = [];
		bases = [];
	}

	public function hasMappings():Bool
	{
		return bases.length > 0;
	}

	public function getMappings(modPath:String):Array<FolderMapping>
	{
		var list = mods.get(normalize(modPath));
		return list != null ? [for (item in list) {from: item.from.join("/"), to: item.to.join("/")}] : [];
	}

	public function resolve(path:String, rawExists:String->Bool):Null<String>
	{
		var key = normalize(path);
		var base = findBase(key);

		if (base == null || key == base)
			return null;

		var rel = split(key.substr(base.length + 1));

		for (rule in mods.get(base))
		{
			if (rel.length < rule.to.length)
				continue;

			var captures:Array<String> = [];

			if (!matches(rel, rule.to, captures))
				continue;

			var candidate = join(base, fill(rule.from, captures).concat(rel.slice(rule.to.length)));

			if (rawExists(candidate))
				return candidate;
		}

		return null;
	}

	public function isDirectory(path:String, rawIsDirectory:String->Bool, rawRead:String->Array<String>):Bool
	{
		var key = normalize(path);
		var base = findBase(key);

		if (base == null || key == base)
			return false;

		var rel = split(key.substr(base.length + 1));

		for (rule in mods.get(base))
			if (ruleChildren(base, rel, rule, rawIsDirectory, rawRead) != null)
				return true;

		return false;
	}

	public function children(path:String, rawIsDirectory:String->Bool, rawRead:String->Array<String>):Array<String>
	{
		var key = normalize(path);
		var base = findBase(key);
		var result:Array<String> = [];

		if (base == null)
			return result;

		var rel = key == base ? [] : split(key.substr(base.length + 1));

		for (rule in mods.get(base))
		{
			var names = ruleChildren(base, rel, rule, rawIsDirectory, rawRead);

			if (names != null)
				for (name in names)
					if (!result.contains(name))
						result.push(name);
		}

		return result;
	}

	function ruleChildren(base:String, rel:Array<String>, rule:CompiledMapping, rawIsDirectory:String->Bool, rawRead:String->Array<String>):Null<Array<String>>
	{
		var captures:Array<String> = [];

		if (rel.length >= rule.to.length)
		{
			if (!matches(rel, rule.to, captures))
				return null;

			var real = join(base, fill(rule.from, captures).concat(rel.slice(rule.to.length)));
			return rawIsDirectory(real) ? rawRead(real) : null;
		}

		if (!matches(rel, rule.to.slice(0, rel.length), captures))
			return null;

		var next = rule.to[rel.length];
		var candidates:Array<String>;

		if (next == "*")
		{
			var fromIndex = wildcardPosition(rule.from, captures.length);
			var parent = join(base, fill(rule.from.slice(0, fromIndex), captures));
			candidates = rawIsDirectory(parent) ? rawRead(parent) : [];
		}
		else
			candidates = [next];

		var result:Array<String> = [];

		for (candidate in candidates)
			if (ruleChildren(base, rel.concat([candidate]), rule, rawIsDirectory, rawRead) != null)
				result.push(candidate);

		return result.length > 0 ? result : null;
	}

	function findBase(key:String):Null<String>
	{
		for (base in bases)
			if (key == base || StringTools.startsWith(key, base + "/"))
				return base;

		return null;
	}

	static function matches(rel:Array<String>, pattern:Array<String>, captures:Array<String>):Bool
	{
		for (i in 0...pattern.length)
		{
			if (pattern[i] == "*")
				captures.push(rel[i]);
			else if (pattern[i].toLowerCase() != rel[i].toLowerCase())
				return false;
		}

		return true;
	}

	static function fill(pattern:Array<String>, captures:Array<String>):Array<String>
	{
		var index = 0;
		var result:Array<String> = [];

		for (segment in pattern)
		{
			if (segment != "*")
				result.push(segment);
			else if (index < captures.length)
				result.push(captures[index++]);
			else
				break;
		}

		return result;
	}

	static function wildcardPosition(pattern:Array<String>, index:Int):Int
	{
		var count = 0;

		for (i in 0...pattern.length)
			if (pattern[i] == "*")
			{
				if (count == index)
					return i;

				count++;
			}

		return pattern.length;
	}

	static function wildcards(pattern:Array<String>):Int
	{
		return pattern.filter(segment -> segment == "*").length;
	}

	static function join(base:String, parts:Array<String>):String
	{
		return parts.length == 0 ? base : base + "/" + parts.join("/");
	}

	static function split(path:String):Array<String>
	{
		return [for (part in StringTools.replace(path, "\\", "/").split("/")) if (part != "" && part != ".") part];
	}

	public static function normalize(path:String):String
	{
		if (path == null)
			return "";

		var unified = StringTools.replace(path, "\\", "/");
		var absolute = StringTools.startsWith(unified, "/");
		var result = split(unified).join("/");
		return absolute ? "/" + result : result;
	}
}
