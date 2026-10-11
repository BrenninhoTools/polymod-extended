package polymod.extended;

import haxe.Json;

typedef ModListEntry =
{
	id:String,
	enabled:Bool
}

class ModList
{
	public var entries(default, null):Array<ModListEntry>;

	public var length(get, never):Int;

	public function new(?entries:Array<ModListEntry>)
	{
		this.entries = [];

		if (entries != null)
			for (entry in entries)
				if (entry != null && entry.id != null && indexOf(entry.id) == -1)
					this.entries.push({id: entry.id, enabled: entry.enabled == true});
	}

	public function indexOf(id:String):Int
	{
		for (i in 0...entries.length)
			if (entries[i].id == id)
				return i;

		return -1;
	}

	public function has(id:String):Bool
	{
		return indexOf(id) != -1;
	}

	public function isEnabled(id:String):Bool
	{
		var index = indexOf(id);
		return index != -1 && entries[index].enabled;
	}

	public function add(id:String, enabled:Bool = true):Void
	{
		if (id == null || has(id))
			return;

		entries.push({id: id, enabled: enabled});
	}

	public function remove(id:String):Bool
	{
		var index = indexOf(id);

		if (index == -1)
			return false;

		entries.splice(index, 1);
		return true;
	}

	public function setEnabled(id:String, enabled:Bool):Void
	{
		var index = indexOf(id);

		if (index == -1)
			add(id, enabled);
		else
			entries[index].enabled = enabled;
	}

	public function toggle(id:String):Bool
	{
		var enabled = !isEnabled(id);
		setEnabled(id, enabled);
		return enabled;
	}

	public function move(id:String, newIndex:Int):Bool
	{
		var index = indexOf(id);

		if (index == -1)
			return false;

		var entry = entries.splice(index, 1)[0];
		var target = newIndex < 0 ? 0 : (newIndex > entries.length ? entries.length : newIndex);
		entries.insert(target, entry);
		return true;
	}

	public function sync(availableIds:Array<String>, enableNew:Bool = true, ?isEnabledByDefault:String->Bool):Void
	{
		entries = entries.filter(entry -> availableIds.contains(entry.id));

		for (id in availableIds)
			if (!has(id))
				add(id, enableNew && (isEnabledByDefault == null || isEnabledByDefault(id)));
	}

	public function getEnabledIds():Array<String>
	{
		return [for (entry in entries) if (entry.enabled) entry.id];
	}

	public function getDisabledIds():Array<String>
	{
		return [for (entry in entries) if (!entry.enabled) entry.id];
	}

	public function clear():Void
	{
		entries = [];
	}

	public function copy():ModList
	{
		return new ModList(entries);
	}

	public function toJson(pretty:Bool = false):String
	{
		return Json.stringify(entries, null, pretty ? "\t" : null);
	}

	public static function fromJson(json:String):ModList
	{
		if (json == null || StringTools.trim(json).length == 0)
			return new ModList();

		try
		{
			var data:Dynamic = Json.parse(json);

			if (!Std.isOfType(data, Array))
				return new ModList();

			var result:Array<ModListEntry> = [];

			for (item in (data : Array<Dynamic>))
			{
				var id:Dynamic = Reflect.field(item, "id");

				if (Std.isOfType(id, String))
					result.push({id: id, enabled: Reflect.field(item, "enabled") == true});
			}

			return new ModList(result);
		}
		catch (e:Dynamic)
		{
			return new ModList();
		}
	}

	function get_length():Int
	{
		return entries.length;
	}
}
