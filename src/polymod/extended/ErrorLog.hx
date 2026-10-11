package polymod.extended;

import polymod.Polymod.PolymodError;
import polymod.Polymod.PolymodErrorType;

class ErrorLog
{
	public var entries(default, null):Array<PolymodError> = [];

	public var maxEntries:Int;

	public var errorCount(get, never):Int;

	public var warningCount(get, never):Int;

	public function new(maxEntries:Int = 256)
	{
		this.maxEntries = maxEntries;
	}

	public function add(error:PolymodError):Void
	{
		if (error == null)
			return;

		entries.push(error);

		if (maxEntries > 0)
			while (entries.length > maxEntries)
				entries.shift();
	}

	public function filter(severity:PolymodErrorType):Array<PolymodError>
	{
		return entries.filter(entry -> entry.severity == severity);
	}

	public function hasErrors():Bool
	{
		return errorCount > 0;
	}

	public function clear():Void
	{
		entries = [];
	}

	public function format(?severity:PolymodErrorType):String
	{
		var list = severity == null ? entries : filter(severity);
		return [for (entry in list) '[${entry.severity}] (${entry.origin}) ${entry.code}: ${entry.message}'].join("\n");
	}

	function get_errorCount():Int
	{
		return filter(ERROR).length;
	}

	function get_warningCount():Int
	{
		return filter(WARNING).length;
	}
}
