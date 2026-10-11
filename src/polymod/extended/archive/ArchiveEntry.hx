package polymod.extended.archive;

class ArchiveEntry
{
	public var path:String;

	public var size:Int = 0;

	public var packedSize:Int = 0;

	public var directory:Bool = false;

	public var offset:Int = 0;

	public var method:Int = 0;

	public var crc:Null<Int> = null;

	public var unsupportedReason:Null<String> = null;

	public var supported(get, never):Bool;

	public function new(path:String)
	{
		this.path = path;
	}

	function get_supported():Bool
	{
		return unsupportedReason == null;
	}
}
