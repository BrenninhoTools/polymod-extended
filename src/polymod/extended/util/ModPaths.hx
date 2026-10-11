package polymod.extended.util;

import haxe.io.Path;

class ModPaths
{
	public static var folderName:String = "mods";

	public static function gameFolder():String
	{
		#if sys
		try
		{
			var program = Sys.programPath();

			if (program != null && program.length > 0)
			{
				var directory = Path.directory(program);

				#if mac
				if (StringTools.endsWith(directory, ".app/Contents/MacOS"))
					return Path.directory(Path.directory(Path.directory(directory)));
				#end

				return directory.length > 0 ? directory : Sys.getCwd();
			}
		}
		catch (e:Dynamic) {}

		return Sys.getCwd();
		#else
		return "";
		#end
	}

	public static function bundledRoot():Null<String>
	{
		#if (sys && !mobile && !android && !ios)
		return Path.join([gameFolder(), folderName]);
		#else
		return null;
		#end
	}

	public static function userRoot(gameName:String, ?company:String):String
	{
		var name = sanitize(gameName);
		var owner = company != null ? sanitize(company) : null;

		#if (android && lime)
		var packageName = androidPackage();

		if (packageName != null)
			return '/storage/emulated/0/Android/data/$packageName/files/$folderName';

		return Path.join([lime.system.System.applicationStorageDirectory, folderName]);
		#elseif (ios && lime)
		return Path.join([lime.system.System.documentsDirectory, folderName]);
		#elseif sys
		var system = Sys.systemName();

		if (system == "Windows")
		{
			var appData = Sys.getEnv("APPDATA");
			var base = appData != null && appData.length > 0 ? appData : Path.join([home(), "AppData", "Roaming"]);
			return owner != null ? Path.join([base, owner, name, folderName]) : Path.join([base, name, folderName]);
		}

		if (system == "Mac")
			return Path.join([home(), "Library", "Application Support", owner != null ? '$owner/$name' : name, folderName]);

		var data = Sys.getEnv("XDG_DATA_HOME");
		var base = data != null && data.length > 0 ? data : Path.join([home(), ".local", "share"]);
		return owner != null ? Path.join([base, owner, name, folderName]) : Path.join([base, name, folderName]);
		#else
		return folderName;
		#end
	}

	public static function androidSharedRoot(name:String):String
	{
		return '/storage/emulated/0/${sanitize(name)}/$folderName';
	}

	public static function defaultRoots(gameName:String, ?company:String):Array<String>
	{
		var result:Array<String> = [];
		var bundled = bundledRoot();

		if (bundled != null)
			result.push(bundled);

		var user = userRoot(gameName, company);

		if (!result.contains(user))
			result.push(user);

		return result;
	}

	public static function ensure(path:String):Bool
	{
		#if sys
		try
		{
			if (!sys.FileSystem.exists(path))
				sys.FileSystem.createDirectory(path);

			return sys.FileSystem.isDirectory(path);
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		return false;
		#end
	}

	public static function isWritable(path:String):Bool
	{
		#if sys
		if (!ensure(path))
			return false;

		var probe = Path.join([path, ".polymod-extended-write-test"]);

		try
		{
			sys.io.File.saveContent(probe, "ok");
			sys.FileSystem.deleteFile(probe);
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		return false;
		#end
	}

	public static function sanitize(name:String):String
	{
		var clean = ~/[<>:"\/\\|?*\x00-\x1F]/g.replace(name != null ? name : "", "_");
		clean = StringTools.trim(clean);

		while (StringTools.endsWith(clean, "."))
			clean = clean.substr(0, clean.length - 1);

		return clean.length > 0 ? clean : "game";
	}

	#if sys
	static function home():String
	{
		var value = Sys.getEnv(Sys.systemName() == "Windows" ? "USERPROFILE" : "HOME");
		return value != null ? value : Sys.getCwd();
	}
	#end

	#if (android && lime)
	static function androidPackage():Null<String>
	{
		var application = lime.app.Application.current;

		if (application == null || application.meta == null)
			return null;

		var value = application.meta.get("packageName");
		return value != null && value.length > 0 ? value : null;
	}
	#end
}
