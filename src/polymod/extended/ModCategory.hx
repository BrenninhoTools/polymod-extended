package polymod.extended;

import haxe.Json;

class ModCategory
{
	public static var metadataFile:String = "_category.json";

	public var id(default, null):String;

	public var title:String;

	public var description:String = "";

	public var order:Int = 0;

	public var hidden:Bool = false;

	public var folder(default, null):Bool;

	public var data:Dynamic = null;

	public var mods(default, null):Array<String> = [];

	public function new(id:String, folder:Bool)
	{
		this.id = id;
		this.folder = folder;
		this.title = id;
	}

	public function apply(json:String, ?errors:Array<String>):Void
	{
		if (json == null || StringTools.trim(json).length == 0)
			return;

		var data:Dynamic;

		try
		{
			data = Json.parse(json);
		}
		catch (e:Dynamic)
		{
			if (errors != null)
				errors.push('category "$id" has an invalid $metadataFile: ${Std.string(e)}');

			return;
		}

		if (data == null || Type.typeof(data) != TObject)
			return;

		var title:Dynamic = Reflect.field(data, "title");
		var description:Dynamic = Reflect.field(data, "description");
		var order:Dynamic = Reflect.field(data, "order");
		var hidden:Dynamic = Reflect.field(data, "hidden");

		if (Std.isOfType(title, String))
			this.title = title;

		if (Std.isOfType(description, String))
			this.description = description;

		if (Std.isOfType(order, Int))
			this.order = order;

		if (Std.isOfType(hidden, Bool))
			this.hidden = hidden;

		this.data = Reflect.field(data, "data");
	}

	public static function sort(categories:Array<ModCategory>):Void
	{
		categories.sort((a, b) ->
		{
			if (a.order != b.order)
				return a.order - b.order;

			var left = a.title.toLowerCase();
			var right = b.title.toLowerCase();
			return left < right ? -1 : (left > right ? 1 : 0);
		});
	}
}
