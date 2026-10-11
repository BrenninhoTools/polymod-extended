package polymod.extended.scripting;

import hscript.Parser;
import hscript.Printer;
import polymod.Polymod;
import polymod.Polymod.ModMetadata;
import polymod.extended.hooks.ModHooks;
import polymod.extended.scripting.ScriptSandbox.SandboxInterp;
import polymod.util.Util;

class ModScript
{
	public static inline final STOP:String = "##POLYMOD_EXTENDED_STOP##";

	public static inline final CONTINUE:String = "##POLYMOD_EXTENDED_CONTINUE##";

	public var name(default, null):String;

	public var modId(default, null):Null<String>;

	public var path(default, null):Null<String>;

	public var interp(default, null):SandboxInterp;

	public var active(default, null):Bool = false;

	public var lastError(default, null):Null<String> = null;

	var source:String;
	var hooks:Array<{name:String, callback:ModEvent->Void}> = [];

	public function new(source:String, name:String, ?modId:String, ?path:String)
	{
		this.source = source != null ? source : "";
		this.name = name;
		this.modId = modId;
		this.path = path;
		interp = new SandboxInterp();
		setupGlobals();
	}

	public static function fromString(source:String, name:String, ?modId:String):ModScript
	{
		var script = new ModScript(source, name, modId);
		script.execute();
		return script;
	}

	public function execute():Bool
	{
		var parser = new Parser();
		parser.allowTypes = true;
		parser.allowJSON = true;
		parser.allowMetadata = true;

		try
		{
			var program = parser.parseString(source, name);
			interp.execute(program);
			active = true;
			return true;
		}
		catch (e:Dynamic)
		{
			fail(e);
			return false;
		}
	}

	public function exists(functionName:String):Bool
	{
		if (!active || !interp.variables.exists(functionName))
			return false;

		return Reflect.isFunction(interp.variables.get(functionName));
	}

	public function call(functionName:String, ?args:Array<Dynamic>):Dynamic
	{
		if (!exists(functionName))
			return null;

		try
		{
			return Reflect.callMethod(null, interp.variables.get(functionName), args != null ? args : []);
		}
		catch (e:Dynamic)
		{
			fail(e, functionName);
			return null;
		}
	}

	public function get(variable:String):Dynamic
	{
		return interp.variables.get(variable);
	}

	public function set(variable:String, value:Dynamic):Void
	{
		interp.variables.set(variable, value);
	}

	public function has(variable:String):Bool
	{
		return interp.variables.exists(variable);
	}

	public function destroy():Void
	{
		if (active)
			call("onDestroy");

		for (hook in hooks)
			ModHooks.remove(hook.name, hook.callback);

		hooks = [];
		active = false;
	}

	function setupGlobals():Void
	{
		var mod = modId != null ? PolymodExtended.getMod(modId) : null;

		interp.variables.set("STOP", STOP);
		interp.variables.set("CONTINUE", CONTINUE);
		interp.variables.set("script", {name: name, path: path, modId: modId});
		interp.variables.set("mod", mod != null ? new ModScriptContext(mod) : null);
		interp.variables.set("print", Reflect.makeVarArgs(args -> ModScripts.print(this, [for (arg in args) Std.string(arg)].join(" "))));
		interp.variables.set("hook", (hookName:String, callback:ModEvent->Void, ?priority:Int) ->
		{
			var safe = (event:ModEvent) -> callback(event);
			hooks.push({name: hookName, callback: safe});
			ModHooks.add(hookName, safe, modId, priority != null ? priority : 0);
		});
		interp.variables.set("callScripts", (functionName:String, ?args:Array<Dynamic>) -> ModScripts.call(functionName, args));
	}

	function fail(error:Dynamic, ?functionName:String):Void
	{
		var message = describe(error);
		lastError = functionName != null ? '$functionName: $message' : message;
		ModScripts.reportError(this, lastError);
	}

	static function describe(error:Dynamic):String
	{
		try
		{
			#if hscriptPos
			if (Std.isOfType(error, hscript.Expr.Error))
				return Printer.errorToString(error);
			#else
			if (Reflect.isEnumValue(error) && Type.getEnum(error) == hscript.Expr.Error)
				return Printer.errorToString(error);
			#end
		}
		catch (e:Dynamic) {}

		if (Std.isOfType(error, haxe.Exception))
			return (error : haxe.Exception).message;

		return Std.string(error);
	}
}

class ModScriptContext
{
	public var id(default, null):String;

	public var title(default, null):String;

	public var version(default, null):String;

	public var path(default, null):String;

	public function new(mod:ModMetadata)
	{
		id = mod.id;
		title = mod.title;
		version = mod.modVersion != null ? mod.modVersion.toString() : "";
		path = mod.modPath != null ? mod.modPath : Util.pathJoin(PolymodExtended.config.modRoot, mod.dirName);
	}

	public function getSetting(key:String):Dynamic
	{
		return PolymodExtended.getSetting(id, key);
	}

	public function setSetting(key:String, value:Dynamic):Bool
	{
		return PolymodExtended.setSetting(id, key, value);
	}

	public function getData():Dynamic
	{
		return PolymodExtended.getModData(id);
	}

	public function exists(file:String):Bool
	{
		var full = resolve(file);
		return full != null && PolymodExtended.fileSystem.exists(full);
	}

	public function readText(file:String):Null<String>
	{
		var full = resolve(file);
		return full != null && PolymodExtended.fileSystem.exists(full) ? PolymodExtended.fileSystem.getFileContent(full) : null;
	}

	public function readJson(file:String):Dynamic
	{
		var text = readText(file);

		if (text == null)
			return null;

		try
		{
			return haxe.Json.parse(text);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	public function isLoaded():Bool
	{
		return PolymodExtended.isModLoaded(id);
	}

	function resolve(file:String):Null<String>
	{
		var relative = polymod.extended.archive.Archive.normalizePath(file);
		return relative != null && relative.length > 0 ? Util.pathJoin(path, relative) : null;
	}
}
