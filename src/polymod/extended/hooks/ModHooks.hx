package polymod.extended.hooks;

import polymod.Polymod;

class ModEvent
{
	public var name(default, null):String;

	public var data:Dynamic;

	public var result:Dynamic = null;

	public var cancelled(default, null):Bool = false;

	public var stopped(default, null):Bool = false;

	public var cancelable(default, null):Bool;

	public function new(name:String, ?data:Dynamic, cancelable:Bool = true)
	{
		this.name = name;
		this.data = data;
		this.cancelable = cancelable;
	}

	public function cancel():Void
	{
		if (cancelable)
			cancelled = true;
	}

	public function stopPropagation():Void
	{
		stopped = true;
	}
}

private typedef HookListener =
{
	callback:ModEvent->Void,
	priority:Int,
	modId:Null<String>,
	once:Bool,
	order:Int,
	errors:Int
}

class ModHooks
{
	public static inline final MOD_HOOK_ERROR:PolymodErrorCode = "mod_hook_error";

	public static var maxErrors:Int = 3;

	static var listeners:Map<String, Array<HookListener>> = [];
	static var counter:Int = 0;

	public static function add(name:String, callback:ModEvent->Void, ?modId:String, priority:Int = 0):Void
	{
		addListener(name, callback, modId, priority, false);
	}

	public static function once(name:String, callback:ModEvent->Void, ?modId:String, priority:Int = 0):Void
	{
		addListener(name, callback, modId, priority, true);
	}

	public static function remove(name:String, callback:ModEvent->Void):Bool
	{
		var list = listeners.get(name);

		if (list == null)
			return false;

		for (listener in list)
			if (Reflect.compareMethods(listener.callback, callback))
			{
				list.remove(listener);
				return true;
			}

		return false;
	}

	public static function has(name:String):Bool
	{
		var list = listeners.get(name);
		return list != null && list.length > 0;
	}

	public static function count(name:String):Int
	{
		var list = listeners.get(name);
		return list != null ? list.length : 0;
	}

	public static function names():Array<String>
	{
		var result = [for (name => list in listeners) if (list.length > 0) name];
		result.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	public static function call(name:String, ?data:Dynamic, cancelable:Bool = true):ModEvent
	{
		var event = new ModEvent(name, data, cancelable);
		var list = listeners.get(name);

		if (list == null || list.length == 0)
			return event;

		for (listener in list.copy())
		{
			if (listener.once)
				list.remove(listener);

			try
			{
				listener.callback(event);
			}
			catch (e:Dynamic)
			{
				listener.errors++;
				var owner = listener.modId != null ? 'mod "${listener.modId}"' : "a listener";
				Polymod.error(MOD_HOOK_ERROR, 'Hook "$name" from $owner failed: ${Std.string(e)}');

				if (maxErrors > 0 && listener.errors >= maxErrors)
				{
					list.remove(listener);
					Polymod.warning(MOD_HOOK_ERROR, 'Hook "$name" from $owner was removed after ${listener.errors} errors');
				}
			}

			if (event.stopped)
				break;
		}

		return event;
	}

	public static function clearMod(modId:String):Void
	{
		for (name => list in listeners)
			listeners.set(name, list.filter(listener -> listener.modId != modId));
	}

	public static function clearMods():Void
	{
		for (name => list in listeners)
			listeners.set(name, list.filter(listener -> listener.modId == null));
	}

	public static function clear(?name:String):Void
	{
		if (name == null)
			listeners = [];
		else
			listeners.remove(name);
	}

	static function addListener(name:String, callback:ModEvent->Void, modId:Null<String>, priority:Int, once:Bool):Void
	{
		if (name == null || callback == null)
			return;

		var list = listeners.get(name);

		if (list == null)
		{
			list = [];
			listeners.set(name, list);
		}

		list.push({
			callback: callback,
			priority: priority,
			modId: modId,
			once: once,
			order: counter++,
			errors: 0
		});
		list.sort((a, b) -> a.priority != b.priority ? b.priority - a.priority : a.order - b.order);
	}
}
