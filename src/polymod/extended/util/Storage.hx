package polymod.extended.util;

class Storage
{
	public static var webPrefix:String = "polymod-extended:";

	static var memory:Map<String, String> = [];

	public static function read(key:String):Null<String>
	{
		if (key == null)
			return null;

		#if sys
		try
		{
			if (sys.FileSystem.exists(key) && !sys.FileSystem.isDirectory(key))
				return sys.io.File.getContent(key);
		}
		catch (e:Dynamic) {}

		return null;
		#elseif js
		var storage = getLocalStorage();

		if (storage != null)
		{
			try
			{
				return storage.getItem(webPrefix + key);
			}
			catch (e:Dynamic) {}
		}

		return memory.get(key);
		#else
		return memory.get(key);
		#end
	}

	public static function write(key:String, value:String):Bool
	{
		if (key == null)
			return false;

		#if sys
		try
		{
			var directory = haxe.io.Path.directory(key);

			if (directory.length > 0 && !sys.FileSystem.exists(directory))
				sys.FileSystem.createDirectory(directory);

			sys.io.File.saveContent(key, value);
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#elseif js
		var storage = getLocalStorage();

		if (storage != null)
		{
			try
			{
				storage.setItem(webPrefix + key, value);
				return true;
			}
			catch (e:Dynamic) {}
		}

		memory.set(key, value);
		return true;
		#else
		memory.set(key, value);
		return true;
		#end
	}

	public static function remove(key:String):Bool
	{
		if (key == null)
			return false;

		#if sys
		try
		{
			if (sys.FileSystem.exists(key) && !sys.FileSystem.isDirectory(key))
			{
				sys.FileSystem.deleteFile(key);
				return true;
			}
		}
		catch (e:Dynamic) {}

		return false;
		#elseif js
		var storage = getLocalStorage();

		if (storage != null)
		{
			try
			{
				storage.removeItem(webPrefix + key);
			}
			catch (e:Dynamic) {}
		}

		return memory.remove(key) || storage != null;
		#else
		return memory.remove(key);
		#end
	}

	#if js
	static function getLocalStorage():Dynamic
	{
		try
		{
			return js.Syntax.code("(typeof globalThis.localStorage !== 'undefined' && globalThis.localStorage !== null) ? globalThis.localStorage : null");
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}
	#end
}
