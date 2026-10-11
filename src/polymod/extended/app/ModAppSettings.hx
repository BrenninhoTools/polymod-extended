package polymod.extended.app;

import haxe.io.Bytes;
import polymod.Polymod;
import polymod.Polymod.ModMetadata;
import polymod.extended.util.Signal;
import polymod.util.Util;

enum abstract AppSettingType(String) from String to String
{
	var STRING = "string";
	var INT = "int";
	var FLOAT = "float";
	var BOOL = "bool";
	var COLOR = "color";
	var FILE = "file";
}

typedef AppSettingRule =
{
	type:AppSettingType,
	?min:Float,
	?max:Float,
	?maxLength:Int,
	?extensions:Array<String>
}

typedef AppSettingValue =
{
	key:String,
	value:Dynamic,
	modId:String,
	?bytes:Bytes
}

class ModAppSettings
{
	public static inline final APP_SETTING_INVALID:PolymodErrorCode = "app_setting_invalid";

	public static inline final APP_SETTING_BLOCKED:PolymodErrorCode = "app_setting_blocked";

	public static final onChanged:Signal<Map<String, AppSettingValue>> = new Signal();

	public static var rules(default, null):Map<String, AppSettingRule> = [];

	public static var values(default, null):Map<String, AppSettingValue> = [];

	public static var applyToWindow:Bool = true;

	static var defaults:Map<String, Dynamic> = null;

	public static function allow(key:String, rule:AppSettingRule):Void
	{
		rules.set(key, rule);
	}

	public static function block(key:String):Void
	{
		rules.remove(key);
	}

	public static function allowDefaults():Void
	{
		allow("title", {type: STRING, maxLength: 100});
		allow("icon", {type: FILE, extensions: ["png"]});
		allow("fps", {type: INT, min: 30, max: 360});
		allow("width", {type: INT, min: 320, max: 7680});
		allow("height", {type: INT, min: 240, max: 4320});
		allow("fullscreen", {type: BOOL});
		allow("antialiasing", {type: BOOL});
		allow("backgroundColor", {type: COLOR});
	}

	public static function get(key:String):Dynamic
	{
		var entry = values.get(key);
		return entry != null ? entry.value : null;
	}

	public static function getSource(key:String):Null<String>
	{
		var entry = values.get(key);
		return entry != null ? entry.modId : null;
	}

	public static function refresh(loadedMods:Array<ModMetadata>):Map<String, AppSettingValue>
	{
		var result:Map<String, AppSettingValue> = [];

		for (mod in loadedMods)
		{
			var app:Dynamic = PolymodExtended.getModOptions(mod.id).app;

			if (app == null)
				continue;

			for (key in Reflect.fields(app))
			{
				var rule = rules.get(key);

				if (rule == null)
				{
					Polymod.warning(APP_SETTING_BLOCKED, 'Mod "${mod.id}" tried to change "app.$key", which this game does not allow', INIT);
					continue;
				}

				var raw:Dynamic = Reflect.field(app, key);
				var entry = validate(mod, key, raw, rule);

				if (entry == null)
				{
					Polymod.warning(APP_SETTING_INVALID, 'Mod "${mod.id}" has an invalid value for "app.$key"', INIT);
					continue;
				}

				result.set(key, entry);
			}
		}

		var changed = !sameValues(values, result);
		values = result;

		if (changed)
		{
			if (applyToWindow)
				applyWindow();

			onChanged.dispatch(values);
		}

		return values;
	}

	public static function reset():Void
	{
		values = [];

		if (applyToWindow)
			applyWindow();

		onChanged.dispatch(values);
	}

	public static function parseColor(value:Dynamic):Null<Int>
	{
		if (Std.isOfType(value, Int))
			return value;

		if (!Std.isOfType(value, String))
			return null;

		var text = StringTools.trim((value : String));

		if (StringTools.startsWith(text, "#"))
			text = text.substr(1);
		else if (StringTools.startsWith(text.toLowerCase(), "0x"))
			text = text.substr(2);

		if (!~/^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.match(text))
			return null;

		var parsed = Std.parseInt("0x" + text);

		if (parsed == null)
			return null;

		return text.length == 6 ? (0xFF000000 | parsed) : parsed;
	}

	static function validate(mod:ModMetadata, key:String, raw:Dynamic, rule:AppSettingRule):Null<AppSettingValue>
	{
		switch (rule.type)
		{
			case STRING:
				if (!Std.isOfType(raw, String))
					return null;

				var text:String = raw;

				if (rule.maxLength != null && text.length > rule.maxLength)
					text = text.substr(0, rule.maxLength);

				return {key: key, value: text, modId: mod.id};

			case INT:
				if (!Std.isOfType(raw, Int) && !Std.isOfType(raw, Float))
					return null;

				var number:Float = raw;

				if (Math.isNaN(number))
					return null;

				return {key: key, value: Std.int(clamp(Math.round(number), rule)), modId: mod.id};

			case FLOAT:
				if (!Std.isOfType(raw, Int) && !Std.isOfType(raw, Float))
					return null;

				var number:Float = raw;
				return Math.isNaN(number) ? null : {key: key, value: clamp(number, rule), modId: mod.id};

			case BOOL:
				return Std.isOfType(raw, Bool) ? {key: key, value: raw, modId: mod.id} : null;

			case COLOR:
				var color = parseColor(raw);
				return color != null ? {key: key, value: color, modId: mod.id} : null;

			case FILE:
				if (!Std.isOfType(raw, String))
					return null;

				var relative = polymod.extended.archive.Archive.normalizePath(raw);

				if (relative == null || relative.length == 0)
					return null;

				if (rule.extensions != null && !rule.extensions.contains(haxe.io.Path.extension(relative).toLowerCase()))
					return null;

				var modPath = mod.modPath != null ? mod.modPath : Util.pathJoin(PolymodExtended.config.modRoot, mod.dirName);
				var bytes = PolymodExtended.fileSystem.getFileBytes(Util.pathJoin(modPath, relative));
				return bytes != null ? {key: key, value: relative, modId: mod.id, bytes: bytes} : null;
		}

		return null;
	}

	static function clamp(value:Float, rule:AppSettingRule):Float
	{
		if (rule.min != null && value < rule.min)
			return rule.min;

		if (rule.max != null && value > rule.max)
			return rule.max;

		return value;
	}

	static function sameValues(a:Map<String, AppSettingValue>, b:Map<String, AppSettingValue>):Bool
	{
		for (key => entry in a)
			if (!b.exists(key) || b.get(key).value != entry.value || b.get(key).modId != entry.modId)
				return false;

		for (key in b.keys())
			if (!a.exists(key))
				return false;

		return true;
	}

	static function applyWindow():Void
	{
		#if (lime && !macro)
		var application = lime.app.Application.current;
		var window = application != null ? application.window : null;

		if (window == null)
			return;

		if (defaults == null)
			defaults = [
				"title" => window.title,
				"fps" => window.frameRate,
				"width" => window.width,
				"height" => window.height,
				"fullscreen" => window.fullscreen
			];

		var title = values.exists("title") ? get("title") : defaults.get("title");

		if (title != null && window.title != title)
			window.title = title;

		var fps:Float = values.exists("fps") ? get("fps") : defaults.get("fps");

		if (window.frameRate != fps)
			window.frameRate = fps;

		var fullscreen:Bool = values.exists("fullscreen") ? get("fullscreen") : defaults.get("fullscreen");

		if (window.fullscreen != fullscreen)
			window.fullscreen = fullscreen;

		if (values.exists("width") || values.exists("height"))
		{
			var width:Int = values.exists("width") ? get("width") : window.width;
			var height:Int = values.exists("height") ? get("height") : window.height;

			if (!window.fullscreen && (window.width != width || window.height != height))
				window.resize(width, height);
		}

		var icon = values.get("icon");

		if (icon != null && icon.bytes != null)
		{
			var image = lime.graphics.Image.fromBytes(icon.bytes);

			if (image != null)
				window.setIcon(image);
		}
		#end
	}
}
