package polymod.extended.scripting;

import haxe.io.Path;
import polymod.Polymod;
import polymod.Polymod.ModMetadata;
import polymod.extended.util.Signal;
import polymod.util.Util;

typedef ScriptMessage =
{
	script:ModScript,
	message:String
}

class ScriptGroup
{
	public var scripts(default, null):Array<ModScript> = [];

	public function new() {}

	public function add(script:ModScript):Void
	{
		if (script != null && !scripts.contains(script))
			scripts.push(script);
	}

	public function call(functionName:String, ?args:Array<Dynamic>):Array<Dynamic>
	{
		var results:Array<Dynamic> = [];

		for (script in scripts.copy())
			if (script.exists(functionName))
				results.push(script.call(functionName, args));

		return results;
	}

	public function callStop(functionName:String, ?args:Array<Dynamic>):Bool
	{
		for (script in scripts.copy())
			if (script.exists(functionName) && script.call(functionName, args) == ModScript.STOP)
				return true;

		return false;
	}

	public function set(variable:String, value:Dynamic):Void
	{
		for (script in scripts)
			script.set(variable, value);
	}

	public function exists(functionName:String):Bool
	{
		for (script in scripts)
			if (script.exists(functionName))
				return true;

		return false;
	}

	public function destroy():Void
	{
		for (script in scripts)
			script.destroy();

		scripts = [];
	}
}

class ModScripts
{
	public static inline final MOD_SCRIPT_ERROR:PolymodErrorCode = "mod_script_error";

	public static inline final MOD_SCRIPT_PRINT:PolymodErrorCode = "mod_script_print";

	public static final onError:Signal<ScriptMessage> = new Signal();

	public static final onPrint:Signal<ScriptMessage> = new Signal();

	public static var folder:String = "scripts";

	public static var extensions:Array<String> = ["hx", "hxs", "hscript"];

	public static var global(default, null):ScriptGroup = new ScriptGroup();

	public static var groups(default, null):Array<ScriptGroup> = [];

	public static var scripts(get, never):Array<ModScript>;

	public static function reload():Array<ModScript>
	{
		destroyAll();

		for (mod in PolymodExtended.loadedMods)
			for (file in listScripts(mod, folder))
				loadInto(global, mod, Util.pathJoin(folder, file));

		global.call("onCreate");
		return global.scripts;
	}

	public static function load(relativePath:String):ScriptGroup
	{
		var group = new ScriptGroup();
		var normalized = polymod.extended.archive.Archive.normalizePath(relativePath);

		if (normalized != null)
			for (mod in PolymodExtended.loadedMods)
			{
				var full = Util.pathJoin(modPath(mod), normalized);

				if (PolymodExtended.fileSystem.exists(full) && !PolymodExtended.fileSystem.isDirectory(full))
					loadInto(group, mod, normalized);
			}

		groups.push(group);
		group.call("onCreate");
		return group;
	}

	public static function loadFolder(relativeFolder:String):ScriptGroup
	{
		var group = new ScriptGroup();

		for (mod in PolymodExtended.loadedMods)
			for (file in listScripts(mod, relativeFolder))
				loadInto(group, mod, Util.pathJoin(relativeFolder, file));

		groups.push(group);
		group.call("onCreate");
		return group;
	}

	public static function fromString(source:String, name:String, ?modId:String):ModScript
	{
		var script = new ModScript(source, name, modId);
		script.execute();
		global.add(script);
		return script;
	}

	public static function call(functionName:String, ?args:Array<Dynamic>):Array<Dynamic>
	{
		var results = global.call(functionName, args);

		for (group in groups.copy())
			results = results.concat(group.call(functionName, args));

		return results;
	}

	public static function callStop(functionName:String, ?args:Array<Dynamic>):Bool
	{
		if (global.callStop(functionName, args))
			return true;

		for (group in groups.copy())
			if (group.callStop(functionName, args))
				return true;

		return false;
	}

	public static function set(variable:String, value:Dynamic):Void
	{
		global.set(variable, value);

		for (group in groups)
			group.set(variable, value);
	}

	public static function update(elapsed:Float):Void
	{
		call("onUpdate", [elapsed]);
	}

	public static function destroyGroup(group:ScriptGroup):Void
	{
		group.destroy();
		groups.remove(group);
	}

	public static function destroyAll():Void
	{
		for (group in groups)
			group.destroy();

		groups = [];
		global.destroy();
	}

	@:allow(polymod.extended.scripting.ModScript)
	static function reportError(script:ModScript, message:String):Void
	{
		var owner = script.modId != null ? 'mod "${script.modId}"' : "a script";
		Polymod.error(MOD_SCRIPT_ERROR, 'Script "${script.name}" from $owner failed: $message');
		onError.dispatch({script: script, message: message});
	}

	@:allow(polymod.extended.scripting.ModScript)
	static function print(script:ModScript, message:String):Void
	{
		Polymod.info(MOD_SCRIPT_PRINT, '[${script.name}] $message');
		onPrint.dispatch({script: script, message: message});
	}

	static function loadInto(group:ScriptGroup, mod:ModMetadata, relativePath:String):Null<ModScript>
	{
		var full = Util.pathJoin(modPath(mod), relativePath);
		var source = PolymodExtended.fileSystem.getFileContent(full);

		if (source == null)
			return null;

		var script = new ModScript(source, '${mod.id}:$relativePath', mod.id, full);

		if (script.execute())
			group.add(script);

		return script;
	}

	static function listScripts(mod:ModMetadata, relativeFolder:String):Array<String>
	{
		var directory = Util.pathJoin(modPath(mod), relativeFolder);
		var fs = PolymodExtended.fileSystem;

		if (!fs.exists(directory) || !fs.isDirectory(directory))
			return [];

		var result = fs.readDirectory(directory).filter(name ->
		{
			var full = Util.pathJoin(directory, name);
			return !fs.isDirectory(full) && extensions.contains(Path.extension(name).toLowerCase());
		});

		result.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	static function modPath(mod:ModMetadata):String
	{
		return mod.modPath != null ? mod.modPath : Util.pathJoin(PolymodExtended.config.modRoot, mod.dirName);
	}

	static function get_scripts():Array<ModScript>
	{
		var result = global.scripts.copy();

		for (group in groups)
			result = result.concat(group.scripts);

		return result;
	}
}
