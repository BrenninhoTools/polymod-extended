package polymod.extended;

import haxe.Json;

class ModSettings
{
	var definitions:Map<String, Array<ModSetting>> = [];

	var values:Map<String, Map<String, Dynamic>> = [];

	public function new() {}

	public function define(modId:String, settings:Array<ModSetting>):Void
	{
		definitions.set(modId, settings != null ? settings.copy() : []);
	}

	public function getDefinitions(modId:String):Array<ModSetting>
	{
		var list = definitions.get(modId);
		return list != null ? list.copy() : [];
	}

	public function getDefinition(modId:String, key:String):Null<ModSetting>
	{
		var list = definitions.get(modId);

		if (list != null)
			for (setting in list)
				if (setting.id == key)
					return setting;

		return null;
	}

	public function has(modId:String, key:String):Bool
	{
		return getDefinition(modId, key) != null;
	}

	public function get(modId:String, key:String):Dynamic
	{
		var definition = getDefinition(modId, key);

		if (definition == null)
			return null;

		var stored = values.get(modId);
		return definition.validate(stored != null ? stored.get(key) : null);
	}

	public function set(modId:String, key:String, value:Dynamic):Bool
	{
		var definition = getDefinition(modId, key);

		if (definition == null || !definition.isValid(value))
			return false;

		var stored = values.get(modId);

		if (stored == null)
		{
			stored = [];
			values.set(modId, stored);
		}

		stored.set(key, definition.validate(value));
		return true;
	}

	public function reset(modId:String, ?key:String):Void
	{
		if (key == null)
		{
			values.remove(modId);
			return;
		}

		var stored = values.get(modId);

		if (stored != null)
			stored.remove(key);
	}

	public function getAll(modId:String):Map<String, Dynamic>
	{
		var result:Map<String, Dynamic> = [];

		for (setting in getDefinitions(modId))
			result.set(setting.id, get(modId, setting.id));

		return result;
	}

	public function clear():Void
	{
		values = [];
	}

	public function toJson(pretty:Bool = false):String
	{
		var data:Dynamic = {};

		for (modId => stored in values)
		{
			var modData:Dynamic = {};
			var count = 0;

			for (key => value in stored)
			{
				Reflect.setField(modData, key, value);
				count++;
			}

			if (count > 0)
				Reflect.setField(data, modId, modData);
		}

		return Json.stringify(data, null, pretty ? "\t" : null);
	}

	public static function fromJson(json:String):ModSettings
	{
		var settings = new ModSettings();

		if (json == null || StringTools.trim(json).length == 0)
			return settings;

		try
		{
			var data:Dynamic = Json.parse(json);

			if (data == null || Type.typeof(data) != TObject)
				return settings;

			for (modId in Reflect.fields(data))
			{
				var modData:Dynamic = Reflect.field(data, modId);

				if (modData == null || Type.typeof(modData) != TObject)
					continue;

				var stored:Map<String, Dynamic> = [];

				for (key in Reflect.fields(modData))
					stored.set(key, Reflect.field(modData, key));

				settings.values.set(modId, stored);
			}
		}
		catch (e:Dynamic) {}

		return settings;
	}
}
