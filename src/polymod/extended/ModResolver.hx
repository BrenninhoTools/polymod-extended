package polymod.extended;

import polymod.Polymod.ModMetadata;
import polymod.extended.util.Platform;
import thx.semver.Version;
import thx.semver.VersionRule;

typedef ResolvedMods =
{
	order:Array<String>,
	skipped:Map<String, String>,
	warnings:Array<String>
}

class ModResolver
{
	public static function resolve(ids:Array<String>, getMetadata:String->Null<ModMetadata>, getOptions:String->ModOptions,
			?gameVersion:String):ResolvedMods
	{
		var skipped:Map<String, String> = [];
		var warnings:Array<String> = [];
		var accepted:Array<String> = [];
		var parsedGameVersion:Null<Version> = gameVersion != null ? parseVersion(gameVersion) : null;

		if (gameVersion != null && parsedGameVersion == null)
			warnings.push('Game version "$gameVersion" is not a valid semantic version, "gameVersion" rules are ignored');

		for (id in ids)
		{
			if (accepted.contains(id) || skipped.exists(id))
				continue;

			var metadata = getMetadata(id);

			if (metadata == null)
			{
				skipped.set(id, "mod was not found");
				continue;
			}

			var options = getOptions(id);

			if (!Platform.matches(options.platforms))
			{
				skipped.set(id, 'mod is not available on this platform (${options.platforms.join(", ")})');
				continue;
			}

			if (options.gameVersion != null && parsedGameVersion != null)
			{
				var rule = parseRule(options.gameVersion);

				if (rule == null)
				{
					skipped.set(id, 'invalid "gameVersion" rule "${options.gameVersion}"');
					continue;
				}

				if (!rule.isSatisfiedBy(parsedGameVersion))
				{
					skipped.set(id, 'requires game version ${options.gameVersion}, running $gameVersion');
					continue;
				}
			}

			var conflict = findConflict(id, metadata, options, accepted, getMetadata, getOptions);

			if (conflict != null)
			{
				skipped.set(id, 'incompatible with "$conflict"');
				continue;
			}

			accepted.push(id);
		}

		return {
			order: sort(accepted, getOptions, warnings),
			skipped: skipped,
			warnings: warnings
		};
	}

	public static function sort(ids:Array<String>, getOptions:String->ModOptions, ?warnings:Array<String>):Array<String>
	{
		var indexed = [for (i in 0...ids.length) {id: ids[i], index: i, priority: getOptions(ids[i]).priority}];
		indexed.sort((a, b) -> a.priority != b.priority ? a.priority - b.priority : a.index - b.index);

		var ordered = [for (item in indexed) item.id];
		var position:Map<String, Int> = [for (i in 0...ordered.length) ordered[i] => i];
		var edges:Map<String, Array<String>> = [for (id in ordered) id => []];

		function addEdge(from:String, to:String):Void
		{
			if (from != to && position.exists(from) && position.exists(to) && !edges.get(from).contains(to))
				edges.get(from).push(to);
		}

		for (id in ordered)
		{
			var options = getOptions(id);

			for (other in options.loadAfter)
				addEdge(other, id);

			for (other in options.loadBefore)
				addEdge(id, other);
		}

		var reach:Map<String, Array<String>> = [for (id in ordered) id => reachable(id, edges)];
		var cyclic:Array<String> = [];

		for (from in ordered)
			for (to in edges.get(from).copy())
				if (reach.get(to).contains(from))
				{
					edges.get(from).remove(to);

					if (!cyclic.contains(from))
						cyclic.push(from);

					if (!cyclic.contains(to))
						cyclic.push(to);
				}

		var incoming:Map<String, Int> = [for (id in ordered) id => 0];

		for (from in ordered)
			for (to in edges.get(from))
				incoming.set(to, incoming.get(to) + 1);

		var ready = [for (id in ordered) if (incoming.get(id) == 0) id];
		var result:Array<String> = [];

		while (ready.length > 0)
		{
			ready.sort((a, b) -> position.get(a) - position.get(b));
			var id = ready.shift();
			result.push(id);

			for (next in edges.get(id))
			{
				incoming.set(next, incoming.get(next) - 1);

				if (incoming.get(next) == 0)
					ready.push(next);
			}
		}

		if (cyclic.length > 0 && warnings != null)
		{
			cyclic.sort((a, b) -> position.get(a) - position.get(b));
			warnings.push('Circular "loadBefore"/"loadAfter" rules between ${cyclic.join(", ")} were ignored');
		}

		return result;
	}

	static function reachable(start:String, edges:Map<String, Array<String>>):Array<String>
	{
		var visited:Array<String> = [];
		var stack = edges.get(start).copy();

		while (stack.length > 0)
		{
			var id = stack.pop();

			if (visited.contains(id))
				continue;

			visited.push(id);

			for (next in edges.get(id))
				stack.push(next);
		}

		return visited;
	}

	static function findConflict(id:String, metadata:ModMetadata, options:ModOptions, accepted:Array<String>, getMetadata:String->Null<ModMetadata>,
			getOptions:String->ModOptions):Null<String>
	{
		for (other in accepted)
		{
			var otherMetadata = getMetadata(other);
			var otherOptions = getOptions(other);

			if (options.incompatible.exists(other) && matchesRule(options.incompatible.get(other), otherMetadata))
				return other;

			if (otherOptions.incompatible.exists(id) && matchesRule(otherOptions.incompatible.get(id), metadata))
				return other;
		}

		return null;
	}

	static function matchesRule(rule:String, metadata:ModMetadata):Bool
	{
		if (rule == null || rule == ModOptions.ANY_VERSION || StringTools.trim(rule).length == 0)
			return true;

		var parsed = parseRule(rule);

		if (parsed == null || metadata == null || metadata.modVersion == null)
			return true;

		return parsed.isSatisfiedBy(metadata.modVersion);
	}

	static function parseRule(rule:String):Null<VersionRule>
	{
		try
		{
			return VersionRule.stringToVersionRule(rule);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	static function parseVersion(version:String):Null<Version>
	{
		try
		{
			return Version.stringToVersion(version);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}
}
