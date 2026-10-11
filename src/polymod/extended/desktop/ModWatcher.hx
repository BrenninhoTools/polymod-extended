package polymod.extended.desktop;

#if sys
import haxe.io.Path;
import polymod.extended.util.Signal;

class ModWatcher
{
	public final onChanged:Signal<Array<String>> = new Signal();

	public var path(default, null):String;

	public var interval:Float;

	public var ignored:Array<String> = [];

	public var enabled:Bool = true;

	var snapshot:Map<String, String> = [];
	var elapsed:Float = 0;

	public var extraPaths(default, null):Array<String>;

	public function new(path:String, interval:Float = 2.0, ?ignored:Array<String>, ?extraPaths:Array<String>)
	{
		this.path = path;
		this.interval = interval;
		this.extraPaths = extraPaths != null ? extraPaths.copy() : [];

		if (ignored != null)
			this.ignored = ignored;

		snapshot = takeSnapshot();
	}

	public function update(delta:Float):Bool
	{
		if (!enabled)
			return false;

		elapsed += delta;

		if (elapsed < interval)
			return false;

		elapsed = 0;
		return check();
	}

	public function check():Bool
	{
		var current = takeSnapshot();
		var changed:Array<String> = [];

		for (file => stamp in current)
			if (snapshot.get(file) != stamp)
				changed.push(file);

		for (file in snapshot.keys())
			if (!current.exists(file))
				changed.push(file);

		snapshot = current;

		if (changed.length == 0)
			return false;

		changed.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		onChanged.dispatch(changed);
		return true;
	}

	public function reset():Void
	{
		elapsed = 0;
		snapshot = takeSnapshot();
	}

	function takeSnapshot():Map<String, String>
	{
		var result:Map<String, String> = [];
		var roots = [path].concat(extraPaths);

		for (i in 0...roots.length)
			if (roots[i] != null && sys.FileSystem.exists(roots[i]) && sys.FileSystem.isDirectory(roots[i]))
				collect(roots[i], i == 0 ? "" : '@$i', result);

		return result;
	}

	function collect(directory:String, relative:String, result:Map<String, String>):Void
	{
		var names:Array<String>;

		try
		{
			names = sys.FileSystem.readDirectory(directory);
		}
		catch (e:Dynamic)
		{
			return;
		}

		for (name in names)
		{
			var full = Path.join([directory, name]);
			var key = relative.length > 0 ? relative + "/" + name : name;

			if (StringTools.startsWith(name, ".") || isIgnored(full))
				continue;

			try
			{
				if (sys.FileSystem.isDirectory(full))
				{
					collect(full, key, result);
					continue;
				}

				var stat = sys.FileSystem.stat(full);
				result.set(key, stat.mtime.getTime() + ":" + stat.size);
			}
			catch (e:Dynamic) {}
		}
	}

	function isIgnored(file:String):Bool
	{
		var normalized = Path.normalize(file);

		for (path in ignored)
			if (path != null && Path.normalize(path) == normalized)
				return true;

		return false;
	}
}
#end
