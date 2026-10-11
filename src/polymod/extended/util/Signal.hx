package polymod.extended.util;

class Signal<T>
{
	var listeners:Array<T->Void> = [];
	var onceListeners:Array<T->Void> = [];

	public var count(get, never):Int;

	public function new() {}

	public function add(listener:T->Void):Void
	{
		if (listener != null && !has(listener))
			listeners.push(listener);
	}

	public function addOnce(listener:T->Void):Void
	{
		if (listener != null && !has(listener))
			onceListeners.push(listener);
	}

	public function remove(listener:T->Void):Void
	{
		listeners.remove(listener);
		onceListeners.remove(listener);
	}

	public function has(listener:T->Void):Bool
	{
		return listeners.contains(listener) || onceListeners.contains(listener);
	}

	public function removeAll():Void
	{
		listeners = [];
		onceListeners = [];
	}

	public function dispatch(value:T):Void
	{
		var current = listeners.copy();
		var once = onceListeners;
		onceListeners = [];

		for (listener in current)
			listener(value);

		for (listener in once)
			listener(value);
	}

	function get_count():Int
	{
		return listeners.length + onceListeners.length;
	}
}
