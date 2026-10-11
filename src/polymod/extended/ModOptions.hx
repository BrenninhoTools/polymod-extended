package polymod.extended;

import haxe.Json;

class ModOptions
{
	public static inline final ANY_VERSION:String = "*";

	public var priority:Int = 0;

	public var loadBefore:Array<String> = [];

	public var loadAfter:Array<String> = [];

	public var incompatible:Map<String, String> = [];

	public var platforms:Array<String> = [];

	public var gameVersion:Null<String> = null;

	public var enabledByDefault:Bool = true;

	public var hidden:Bool = false;

	public var tags:Array<String> = [];

	public var settings:Array<ModSetting> = [];

	public var data:Dynamic = null;

	public var errors:Array<String> = [];

	public function new() {}

	public function hasTag(tag:String):Bool
	{
		var lower = tag.toLowerCase();

		for (value in tags)
			if (value.toLowerCase() == lower)
				return true;

		return false;
	}

	public function getSetting(id:String):Null<ModSetting>
	{
		for (setting in settings)
			if (setting.id == id)
				return setting;

		return null;
	}

	public static function fromJsonString(text:String):ModOptions
	{
		if (text == null || StringTools.trim(text).length == 0)
			return new ModOptions();

		try
		{
			return parse(Json.parse(text));
		}
		catch (e:Dynamic)
		{
			var options = new ModOptions();
			options.errors.push('invalid JSON: ${Std.string(e)}');
			return options;
		}
	}

	public static function parse(json:Dynamic):ModOptions
	{
		var options = new ModOptions();

		if (json == null || Type.typeof(json) != TObject)
		{
			if (json != null)
				options.errors.push("metadata must be a JSON object");

			return options;
		}

		var errors = options.errors;

		var priority:Dynamic = Reflect.field(json, "priority");

		if (priority != null)
		{
			if (Std.isOfType(priority, Int))
				options.priority = priority;
			else
				errors.push("\"priority\" must be an integer");
		}

		options.loadBefore = readStringList(json, "loadBefore", errors);
		options.loadAfter = readStringList(json, "loadAfter", errors);
		options.platforms = readStringList(json, "platforms", errors);
		options.tags = readStringList(json, "tags", errors);

		var incompatible:Dynamic = Reflect.field(json, "incompatible");

		if (incompatible != null)
		{
			if (Std.isOfType(incompatible, Array))
			{
				for (id in readStringList(json, "incompatible", errors))
					options.incompatible.set(id, ANY_VERSION);
			}
			else if (Type.typeof(incompatible) == TObject)
			{
				for (id in Reflect.fields(incompatible))
				{
					var rule:Dynamic = Reflect.field(incompatible, id);

					if (Std.isOfType(rule, String))
						options.incompatible.set(id, rule);
					else
						errors.push('"incompatible.$id" must be a version rule string');
				}
			}
			else
				errors.push("\"incompatible\" must be an array of mod ids or an object of mod ids to version rules");
		}

		var gameVersion:Dynamic = Reflect.field(json, "gameVersion");

		if (gameVersion != null)
		{
			if (Std.isOfType(gameVersion, String))
				options.gameVersion = gameVersion;
			else
				errors.push("\"gameVersion\" must be a version rule string");
		}

		options.enabledByDefault = readBool(json, "enabledByDefault", true, errors);
		options.hidden = readBool(json, "hidden", false, errors);

		var settings:Dynamic = Reflect.field(json, "settings");

		if (settings != null)
		{
			if (Std.isOfType(settings, Array))
			{
				for (item in (settings : Array<Dynamic>))
				{
					var setting = ModSetting.parse(item, errors);

					if (setting == null)
						continue;

					if (options.getSetting(setting.id) != null)
						errors.push('setting "${setting.id}" is defined more than once');
					else
						options.settings.push(setting);
				}
			}
			else
				errors.push("\"settings\" must be an array");
		}

		options.data = Reflect.field(json, "data");
		return options;
	}

	static function readStringList(json:Dynamic, field:String, errors:Array<String>):Array<String>
	{
		var value:Dynamic = Reflect.field(json, field);

		if (value == null)
			return [];

		if (Std.isOfType(value, String))
			return [value];

		if (!Std.isOfType(value, Array))
		{
			errors.push('"$field" must be an array of strings');
			return [];
		}

		var result:Array<String> = [];

		for (item in (value : Array<Dynamic>))
		{
			if (Std.isOfType(item, String))
			{
				if (!result.contains(item))
					result.push(item);
			}
			else
				errors.push('"$field" must only contain strings');
		}

		return result;
	}

	static function readBool(json:Dynamic, field:String, otherwise:Bool, errors:Array<String>):Bool
	{
		var value:Dynamic = Reflect.field(json, field);

		if (value == null)
			return otherwise;

		if (Std.isOfType(value, Bool))
			return value;

		errors.push('"$field" must be true or false');
		return otherwise;
	}
}
