package polymod.extended;

enum abstract ModSettingType(String) from String to String
{
	var BOOL = "bool";
	var INT = "int";
	var FLOAT = "float";
	var STRING = "string";
	var CHOICE = "choice";
}

class ModSetting
{
	public var id(default, null):String;

	public var name(default, null):String;

	public var description(default, null):String;

	public var type(default, null):ModSettingType;

	public var defaultValue(default, null):Dynamic;

	public var min(default, null):Null<Float>;

	public var max(default, null):Null<Float>;

	public var step(default, null):Null<Float>;

	public var choices(default, null):Array<String>;

	public var maxLength(default, null):Null<Int>;

	public function new(id:String, type:ModSettingType, ?defaultValue:Dynamic)
	{
		this.id = id;
		this.type = type;
		this.name = id;
		this.description = "";
		this.choices = [];
		this.defaultValue = fallback();

		if (defaultValue != null)
			this.defaultValue = coerce(defaultValue, this.defaultValue);
	}

	public function validate(value:Dynamic):Dynamic
	{
		return coerce(value, defaultValue);
	}

	public function isValid(value:Dynamic):Bool
	{
		var marker = {};
		return coerce(value, marker) != marker;
	}

	function coerce(value:Dynamic, otherwise:Dynamic):Dynamic
	{
		if (value == null)
			return otherwise;

		switch (type)
		{
			case BOOL:
				return Std.isOfType(value, Bool) ? value : otherwise;

			case INT:
				if (!isNumber(value))
					return otherwise;

				var number:Float = value;

				if (Math.isNaN(number) || Math.round(number) != number)
					return otherwise;

				return Std.int(clamp(number));

			case FLOAT:
				if (!isNumber(value))
					return otherwise;

				var number:Float = value;
				return Math.isNaN(number) ? otherwise : clamp(number);

			case STRING:
				if (!Std.isOfType(value, String))
					return otherwise;

				var text:String = value;
				return maxLength != null && text.length > maxLength ? text.substr(0, maxLength) : text;

			case CHOICE:
				return Std.isOfType(value, String) && choices.contains(value) ? value : otherwise;
		}

		return otherwise;
	}

	function fallback():Dynamic
	{
		return switch (type)
		{
			case BOOL: false;
			case INT: 0;
			case FLOAT: 0.0;
			case STRING: "";
			case CHOICE: choices != null && choices.length > 0 ? choices[0] : null;
		}
	}

	function clamp(value:Float):Float
	{
		if (min != null && value < min)
			return min;

		if (max != null && value > max)
			return max;

		return value;
	}

	static function isNumber(value:Dynamic):Bool
	{
		return Std.isOfType(value, Int) || Std.isOfType(value, Float);
	}

	public static function parse(data:Dynamic, ?errors:Array<String>):Null<ModSetting>
	{
		if (data == null || Type.typeof(data) != TObject)
		{
			report(errors, "a setting must be an object");
			return null;
		}

		var id:Dynamic = Reflect.field(data, "id");

		if (!Std.isOfType(id, String) || (id : String).length == 0)
		{
			report(errors, "a setting is missing its \"id\"");
			return null;
		}

		var rawType:Dynamic = Reflect.field(data, "type");
		var type:ModSettingType = Std.isOfType(rawType, String) ? (rawType : String).toLowerCase() : "";

		if (![BOOL, INT, FLOAT, STRING, CHOICE].contains(type))
		{
			report(errors, 'setting "$id" has an unknown type "$rawType"');
			return null;
		}

		var setting = new ModSetting(id, type);
		setting.name = readString(data, "name", id);
		setting.description = readString(data, "description", "");
		setting.min = readNumber(data, "min");
		setting.max = readNumber(data, "max");
		setting.step = readNumber(data, "step");

		var length = readNumber(data, "maxLength");
		setting.maxLength = length != null ? Std.int(length) : null;

		var choices:Dynamic = Reflect.field(data, "choices");

		if (Std.isOfType(choices, Array))
			setting.choices = [for (choice in (choices : Array<Dynamic>)) if (Std.isOfType(choice, String)) choice];

		if (type == CHOICE && setting.choices.length == 0)
		{
			report(errors, 'setting "$id" is a choice without any "choices"');
			return null;
		}

		var fallbackValue = setting.fallback();
		var rawDefault:Dynamic = Reflect.field(data, "default");
		setting.defaultValue = setting.coerce(rawDefault, fallbackValue);

		if (rawDefault != null && !setting.isValid(rawDefault))
			report(errors, 'setting "$id" has an invalid default value');

		return setting;
	}

	static function readString(data:Dynamic, field:String, otherwise:String):String
	{
		var value:Dynamic = Reflect.field(data, field);
		return Std.isOfType(value, String) ? value : otherwise;
	}

	static function readNumber(data:Dynamic, field:String):Null<Float>
	{
		var value:Dynamic = Reflect.field(data, field);
		return isNumber(value) ? (value : Float) : null;
	}

	static function report(errors:Array<String>, message:String):Void
	{
		if (errors != null)
			errors.push(message);
	}
}
