package polymod.extended.archive;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import polymod.extended.archive.ArchiveSource.IArchiveSource;

class ZipArchive extends Archive
{
	static inline final LOCAL_HEADER:Int = 0x04034b50;
	static inline final CENTRAL_HEADER:Int = 0x02014b50;
	static inline final END_OF_CENTRAL:Int = 0x06054b50;
	static inline final MAX_COMMENT:Int = 0xFFFF;

	public static inline final METHOD_STORE:Int = 0;
	public static inline final METHOD_DEFLATE:Int = 8;

	public function new(source:IArchiveSource, name:String)
	{
		super(source, name, "zip");
		parse();
	}

	public static function isZip(header:Bytes):Bool
	{
		return header.length >= 4
			&& header.get(0) == 0x50
			&& header.get(1) == 0x4B
			&& (header.get(2) == 0x03 || header.get(2) == 0x05)
			&& (header.get(3) == 0x04 || header.get(3) == 0x06);
	}

	function parse():Void
	{
		var endOffset = findEndOfCentralDirectory();

		if (endOffset == -1)
			throw new ArchiveException('"$name" is not a valid zip file');

		var end = source.read(endOffset, 22);
		var entryCount = end.getUInt16(10);
		var directorySize = readUInt32(end, 12);
		var directoryOffset = readUInt32(end, 16);

		if (entryCount == 0xFFFF || directorySize < 0 || directoryOffset < 0)
			throw new ArchiveException('"$name" is a ZIP64 archive, which is not supported');

		if (directoryOffset + directorySize > source.length)
			throw new ArchiveException('"$name" has a corrupted central directory');

		var directory = source.read(directoryOffset, directorySize);
		var position = 0;

		for (i in 0...entryCount)
		{
			if (position + 46 > directory.length || directory.getInt32(position) != CENTRAL_HEADER)
				throw new ArchiveException('"$name" has a corrupted central directory');

			var flags = directory.getUInt16(position + 8);
			var method = directory.getUInt16(position + 10);
			var crc = directory.getInt32(position + 16);
			var packedSize = readUInt32(directory, position + 20);
			var size = readUInt32(directory, position + 24);
			var nameLength = directory.getUInt16(position + 28);
			var extraLength = directory.getUInt16(position + 30);
			var commentLength = directory.getUInt16(position + 32);
			var localOffset = readUInt32(directory, position + 42);
			var fileName = directory.getString(position + 46, nameLength);

			var entry = new ArchiveEntry(fileName);
			entry.directory = StringTools.endsWith(StringTools.replace(fileName, "\\", "/"), "/");
			entry.method = method;
			entry.crc = crc;
			entry.packedSize = packedSize;
			entry.size = size;
			entry.offset = localOffset;

			if (packedSize < 0 || size < 0 || localOffset < 0)
				entry.unsupportedReason = "entries larger than 2 GB and ZIP64 entries are not supported";
			else if (flags & 0x1 != 0)
				entry.unsupportedReason = "encrypted entries are not supported";
			else if (method != METHOD_STORE && method != METHOD_DEFLATE)
				entry.unsupportedReason = 'compression method $method is not supported, use Deflate or Store';

			addEntry(entry);
			position += 46 + nameLength + extraLength + commentLength;
		}
	}

	override function readEntry(entry:ArchiveEntry):Bytes
	{
		if (entry.size == 0)
			return Bytes.alloc(0);

		var header = source.read(entry.offset, 30);

		if (header.getInt32(0) != LOCAL_HEADER)
			throw new ArchiveException('"${entry.path}" has a corrupted local header in "$name"');

		var dataOffset = entry.offset + 30 + header.getUInt16(26) + header.getUInt16(28);
		var data = source.read(dataOffset, entry.packedSize);

		return switch (entry.method)
		{
			case METHOD_STORE: data;
			case METHOD_DEFLATE: inflate(data, entry.size);
			default: throw new ArchiveException('Unsupported compression method ${entry.method}');
		}
	}

	function findEndOfCentralDirectory():Int
	{
		if (source.length < 22)
			return -1;

		var searchLength = source.length < 22 + MAX_COMMENT ? source.length : 22 + MAX_COMMENT;
		var start = source.length - searchLength;
		var tail = source.read(start, searchLength);
		var i = tail.length - 22;

		while (i >= 0)
		{
			if (tail.getInt32(i) == END_OF_CENTRAL)
				return start + i;

			i--;
		}

		return -1;
	}

	public static function inflate(data:Bytes, expectedSize:Int):Bytes
	{
		var inflater = new haxe.zip.InflateImpl(new BytesInput(data), false, false);
		var output = new BytesBuffer();
		var chunk = Bytes.alloc(65536);

		while (true)
		{
			var count = inflater.readBytes(chunk, 0, chunk.length);

			if (count <= 0)
				break;

			output.addBytes(chunk, 0, count);

			if (count < chunk.length)
				break;
		}

		var result = output.getBytes();

		if (expectedSize >= 0 && result.length != expectedSize)
			throw new ArchiveException('Inflated size ${result.length} does not match expected size $expectedSize');

		return result;
	}

	static inline function readUInt32(bytes:Bytes, position:Int):Int
	{
		return bytes.getInt32(position);
	}
}
