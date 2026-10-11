package polymod.extended.scripting;

import hscript.Expr;
import hscript.Interp;
import hscript.Tools;

class ScriptSandbox
{
	public static var globals(default, null):Map<String, Dynamic> = defaultGlobals();

	public static var classes(default, null):Map<String, Class<Dynamic>> = defaultClasses();

	public static function expose(name:String, value:Dynamic):Void
	{
		globals.set(name, value);

		if (Std.isOfType(value, Class))
			classes.set(name, value);
	}

	public static function exposeClass(cls:Class<Dynamic>, ?alias:String):Void
	{
		var fullName = Type.getClassName(cls);
		var shortName = alias != null ? alias : fullName.split(".").pop();
		globals.set(shortName, cls);
		classes.set(shortName, cls);
		classes.set(fullName, cls);
	}

	public static function hide(name:String):Void
	{
		var value = globals.get(name);
		globals.remove(name);
		classes.remove(name);

		if (value != null && Std.isOfType(value, Class))
			classes.remove(Type.getClassName(value));
	}

	public static function reset():Void
	{
		globals = defaultGlobals();
		classes = defaultClasses();
	}

	static function defaultGlobals():Map<String, Dynamic>
	{
		return [
			"Math" => Math,
			"Std" => Std,
			"StringTools" => StringTools,
			"Lambda" => Lambda,
			"Date" => Date,
			"DateTools" => DateTools,
			"Json" => haxe.Json,
			"StringBuf" => StringBuf,
			"EReg" => EReg,
			"ModHooks" => polymod.extended.hooks.ModHooks,
			"ModEvent" => polymod.extended.hooks.ModHooks.ModEvent
		];
	}

	static function defaultClasses():Map<String, Class<Dynamic>> {
		return [
			"Date" => Date,
			"StringBuf" => StringBuf,
			"EReg" => EReg,
			"haxe.ds.StringMap" => haxe.ds.StringMap,
			"StringMap" => haxe.ds.StringMap,
			"haxe.ds.IntMap" => haxe.ds.IntMap,
			"IntMap" => haxe.ds.IntMap
		];
	}
}

class SandboxInterp extends Interp
{
	public function new()
	{
		super();

		for (name => value in ScriptSandbox.globals)
			variables.set(name, value);
	}

	override public function expr(e:Expr):Dynamic
	{
		if (depth == 0)
			switch (Tools.expr(e))
			{
				case EVar(name, _, value):
					#if hscriptPos
					curExpr = e;
					#end
					variables.set(name, value == null ? null : expr(value));
					return null;
				default:
			}

		return super.expr(e);
	}

	override function cnew(cl:String, args:Array<Dynamic>):Dynamic
	{
		var cls = ScriptSandbox.classes.get(cl);

		if (cls == null)
		{
			var value = variables.get(cl);

			if (value != null && Std.isOfType(value, Class))
				cls = value;
		}

		if (cls == null)
			throw 'Class "$cl" is not available to scripts';

		return Type.createInstance(cls, args);
	}
}
