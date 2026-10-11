package polymod.extended.desktop;

#if sys
import haxe.io.Path;
import polymod.extended.structure.ModStructure;
import polymod.extended.structure.StructurePresets;

typedef FileMove =
{
	from:String,
	to:String,
	reason:String
}

typedef SkippedMove =
{
	move:FileMove,
	reason:String
}

typedef OrganizePlan =
{
	folder:String,
	moves:Array<FileMove>,
	skipped:Array<SkippedMove>,
	issues:Array<StructureIssue>,
	?error:String
}

typedef OrganizeResult =
{
	success:Bool,
	moved:Array<FileMove>,
	skipped:Array<SkippedMove>,
	removedFolders:Array<String>,
	?error:String
}

class ModOrganizer
{
	public static function planMod(id:String, ?structure:ModStructure):OrganizePlan
	{
		var location = DesktopMods.getModLocation(id);

		if (location == null)
			return emptyPlan("", 'Mod "$id" is not installed');

		if (!sys.FileSystem.isDirectory(location))
			return emptyPlan(location, 'Mod "$id" is an archive, extract it to a folder to organize it');

		return planFolder(location, structure);
	}

	public static function planFolder(folder:String, ?structure:ModStructure):OrganizePlan
	{
		if (!sys.FileSystem.exists(folder) || !sys.FileSystem.isDirectory(folder))
			return emptyPlan(folder, '"$folder" is not a folder');

		var rules = structure != null ? structure : (PolymodExtended.config.structure != null ? PolymodExtended.config.structure : StructurePresets.generic());
		var files = listFiles(folder);
		var issues = rules.validate(files);
		var moves:Array<FileMove> = [];
		var skipped:Array<SkippedMove> = [];
		var targets:Map<String, Bool> = [];

		for (issue in issues)
		{
			if (issue.suggestion == null || !files.contains(issue.path))
				continue;

			var move:FileMove = {from: issue.path, to: ModStructure.normalizePath(issue.suggestion), reason: issue.message};

			if (move.to == move.from)
				continue;

			var key = move.to.toLowerCase();

			if (targets.exists(key))
				skipped.push({move: move, reason: 'another file is already going to "${move.to}"'});
			else if (sys.FileSystem.exists(Path.join([folder, move.to])))
				skipped.push({move: move, reason: '"${move.to}" already exists'});
			else
			{
				targets.set(key, true);
				moves.push(move);
			}
		}

		return {folder: folder, moves: moves, skipped: skipped, issues: issues};
	}

	public static function organizeMod(id:String, ?structure:ModStructure, reload:Bool = true):OrganizeResult
	{
		var plan = planMod(id, structure);
		var result = apply(plan);

		if (result.success && result.moved.length > 0 && reload && PolymodExtended.initialized)
			PolymodExtended.reload();

		return result;
	}

	public static function organizeFolder(folder:String, ?structure:ModStructure):OrganizeResult
	{
		return apply(planFolder(folder, structure));
	}

	public static function apply(plan:OrganizePlan):OrganizeResult
	{
		if (plan.error != null)
			return {success: false, moved: [], skipped: [], removedFolders: [], error: plan.error};

		var moved:Array<FileMove> = [];
		var skipped = plan.skipped.copy();
		var touched:Array<String> = [];

		for (move in plan.moves)
		{
			var from = Path.join([plan.folder, move.from]);
			var to = Path.join([plan.folder, move.to]);

			try
			{
				if (!sys.FileSystem.exists(from))
				{
					skipped.push({move: move, reason: '"${move.from}" no longer exists'});
					continue;
				}

				if (sys.FileSystem.exists(to))
				{
					skipped.push({move: move, reason: '"${move.to}" already exists'});
					continue;
				}

				createParents(Path.directory(to));
				sys.FileSystem.rename(from, to);
				moved.push(move);

				var directory = Path.directory(move.from);

				if (directory.length > 0 && !touched.contains(directory))
					touched.push(directory);
			}
			catch (e:Dynamic)
			{
				skipped.push({move: move, reason: Std.string(e)});
			}
		}

		var removed = removeEmptyFolders(plan.folder, touched);

		if (moved.length > 0 && DesktopMods.watcher != null)
			DesktopMods.watcher.reset();

		return {success: true, moved: moved, skipped: skipped, removedFolders: removed};
	}

	static function removeEmptyFolders(root:String, folders:Array<String>):Array<String>
	{
		var removed:Array<String> = [];
		var candidates:Array<String> = [];

		for (folder in folders)
		{
			var current = folder;

			while (current.length > 0)
			{
				if (!candidates.contains(current))
					candidates.push(current);

				current = Path.directory(current);
			}
		}

		candidates.sort((a, b) -> b.split("/").length - a.split("/").length);

		for (folder in candidates)
		{
			var full = Path.join([root, folder]);

			try
			{
				if (sys.FileSystem.exists(full) && sys.FileSystem.isDirectory(full) && sys.FileSystem.readDirectory(full).length == 0)
				{
					sys.FileSystem.deleteDirectory(full);
					removed.push(folder);
				}
			}
			catch (e:Dynamic) {}
		}

		return removed;
	}

	static function createParents(directory:String):Void
	{
		if (directory.length > 0 && !sys.FileSystem.exists(directory))
			sys.FileSystem.createDirectory(directory);
	}

	static function listFiles(folder:String, relative:String = ""):Array<String>
	{
		var result:Array<String> = [];
		var current = relative.length > 0 ? Path.join([folder, relative]) : folder;

		for (name in sys.FileSystem.readDirectory(current))
		{
			var child = relative.length > 0 ? relative + "/" + name : name;

			if (sys.FileSystem.isDirectory(Path.join([folder, child])))
				result = result.concat(listFiles(folder, child));
			else
				result.push(child);
		}

		return result;
	}

	static function emptyPlan(folder:String, error:String):OrganizePlan
	{
		return {folder: folder, moves: [], skipped: [], issues: [], error: error};
	}
}
#end
