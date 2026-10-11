package polymod.extended.archive;

import haxe.io.Bytes;
import polymod.extended.archive.ArchiveSource.IArchiveSource;

class Archive
{
	public var name(default, null):String;

	public var format(default, null):String;

	public var source(default, null):IArchiveSource;

	public var entries(default, null):Array<ArchiveEntry> = [];

	var entryMap:Map<String, ArchiveEntry> = [];

	var lowerEntryMap:Map<String, ArchiveEntry> = [];

	public function new(source:IArchiveSource, name:String, format:String)
	{
		this.source = source;
		this.name = name;
		this.format = format;
	}

	public function get(path:String):Null<ArchiveEntry>
	{
		var key = normalizePath(path);

		if (key == null)
			return null;

		var entry = entryMap.get(key);
		return entry != null ? entry : lowerEntryMap.get(key.toLowerCase());
	}

	public function has(path:String):Bool
	{
		return get(path) != null;
	}

	public function read(path:String):Null<Bytes>
	{
		var entry = get(path);

		if (entry == null || entry.directory)
			return null;

		if (!entry.supported)
			throw new ArchiveException('Cannot read "${entry.path}" from "$name": ${entry.unsupportedReason}');

		var data = readEntry(entry);

		if (entry.crc != null && data.length > 0 && haxe.crypto.Crc32.make(data) != entry.crc)
			throw new ArchiveException('Checksum mismatch for "${entry.path}" in "$name"');

		return data;
	}

	public function getUnsupportedEntries():Array<ArchiveEntry>
	{
		return entries.filter(entry -> !entry.directory && !entry.supported);
	}

	public function close():Void
	{
		source.close();
	}

	function readEntry(entry:ArchiveEntry):Bytes
	{
		throw new ArchiveException('Format "$format" cannot read entries');
	}

	function addEntry(entry:ArchiveEntry):Void
	{
		var key = normalizePath(entry.path);

		if (key == null || key.length == 0)
			return;

		entry.path = key;

		if (entryMap.exists(key))
			entries.remove(entryMap.get(key));

		entries.push(entry);
		entryMap.set(key, entry);
		lowerEntryMap.set(key.toLowerCase(), entry);
	}

	public static function normalizePath(path:String):Null<String>
	{
		if (path == null)
			return null;

		var parts:Array<String> = [];

		for (part in StringTools.replace(path, "\\", "/").split("/"))
		{
			if (part == "" || part == ".")
				continue;

			if (part == "..")
				return null;

			parts.push(part);
		}

		return parts.join("/");
	}
}
