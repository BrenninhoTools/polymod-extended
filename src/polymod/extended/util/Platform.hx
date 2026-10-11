package polymod.extended.util;

class Platform
{
	public static var names(get, never):Array<String>;

	static var cachedNames:Array<String> = null;

	public static function matches(list:Array<String>):Bool
	{
		if (list == null || list.length == 0)
			return true;

		var current = names;
		var hasInclude = false;
		var included = false;

		for (raw in list)
		{
			if (raw == null)
				continue;

			var value = StringTools.trim(raw).toLowerCase();

			if (StringTools.startsWith(value, "!"))
			{
				if (current.contains(value.substr(1)))
					return false;
			}
			else
			{
				hasInclude = true;

				if (current.contains(value))
					included = true;
			}
		}

		return !hasInclude || included;
	}

	public static function isMobile():Bool
	{
		return names.contains("mobile");
	}

	public static function isDesktop():Bool
	{
		return names.contains("desktop");
	}

	public static function isWeb():Bool
	{
		return names.contains("web");
	}

	static function get_names():Array<String>
	{
		if (cachedNames == null)
			cachedNames = detect();

		return cachedNames;
	}

	static function detect():Array<String>
	{
		#if android
		return ["android", "mobile"];
		#elseif ios
		return ["ios", "mobile"];
		#elseif (html5 || js)
		return ["html5", "web"];
		#elseif windows
		return ["windows", "desktop"];
		#elseif mac
		return ["mac", "macos", "desktop"];
		#elseif linux
		return ["linux", "desktop"];
		#elseif sys
		return switch (Sys.systemName().toLowerCase())
		{
			case "windows": ["windows", "desktop"];
			case "mac": ["mac", "macos", "desktop"];
			case "linux": ["linux", "desktop"];
			case "bsd": ["bsd", "desktop"];
			case other: [other];
		}
		#else
		return [];
		#end
	}
}
