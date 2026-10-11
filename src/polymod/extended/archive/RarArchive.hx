package polymod.extended.archive;

import haxe.io.Bytes;
import polymod.extended.archive.ArchiveSource.IArchiveSource;

class RarArchive extends Archive
{
	static inline final MAX_INT:Float = 2147483647;

	static inline final RAR4_MAIN:Int = 0x73;
	static inline final RAR4_FILE:Int = 0x74;
	static inline final RAR4_SERVICE:Int = 0x7A;
	static inline final RAR4_END:Int = 0x7B;
	static inline final RAR4_STORE:Int = 0x30;

	static inline final RAR5_MAIN:Int = 1;
	static inline final RAR5_FILE:Int = 2;
	static inline final RAR5_ENCRYPTION:Int = 4;
	static inline final RAR5_END:Int = 5;
	static inline final RAR5_STORE:Int = 0;

	static inline final COMPRESSED_MESSAGE:String = "compressed RAR entries are not supported, re-create the archive with the \"Store\" compression method";

	public var version(default, null):Int;

	public function new(source:IArchiveSource, name:String)
	{
		super(source, name, "rar");

		var header = source.read(0, source.length < 8 ? source.length : 8);

		switch (getVersion(header))
		{
			case 4:
				version = 4;
				parseRar4();
			case 5:
				version = 5;
				parseRar5();
			default:
				throw new ArchiveException('"$name" is not a valid rar file');
		}
	}

	public static function isRar(header:Bytes):Bool
	{
		return getVersion(header) != 0;
	}

	static function getVersion(header:Bytes):Int
	{
		if (header.length < 7
			|| header.get(0) != 0x52
			|| header.get(1) != 0x61
			|| header.get(2) != 0x72
			|| header.get(3) != 0x21
			|| header.get(4) != 0x1A
			|| header.get(5) != 0x07)
			return 0;

		if (header.get(6) == 0x00)
			return 4;

		if (header.get(6) == 0x01 && header.length >= 8 && header.get(7) == 0x00)
			return 5;

		return 0;
	}

	override function readEntry(entry:ArchiveEntry):Bytes
	{
		if (entry.size == 0)
			return Bytes.alloc(0);

		return source.read(entry.offset, entry.size);
	}

	function parseRar4():Void
	{
		var position = 7;

		while (position + 7 <= source.length)
		{
			var base = source.read(position, 7);
			var type = base.get(2);
			var flags = base.getUInt16(3);
			var headerSize = base.getUInt16(5);

			if (headerSize < 7 || position + headerSize > source.length)
				throw new ArchiveException('"$name" has a corrupted block header');

			var header = source.read(position, headerSize);
			var dataSize:Float = 0;

			if (type == RAR4_FILE || type == RAR4_SERVICE)
			{
				if (headerSize < 32)
					throw new ArchiveException('"$name" has a corrupted file header');

				var packedSize:Float = unsigned(header.getInt32(7));
				var size:Float = unsigned(header.getInt32(11));
				var nameOffset = 32;

				if (flags & 0x100 != 0)
				{
					packedSize += unsigned(header.getInt32(32)) * 4294967296.0;
					size += unsigned(header.getInt32(36)) * 4294967296.0;
					nameOffset = 40;
				}

				dataSize = packedSize;

				if (type == RAR4_FILE && !isRar4Link(header))
				{
					var nameLength = header.getUInt16(26);

					if (nameOffset + nameLength > headerSize)
						throw new ArchiveException('"$name" has a corrupted file name');

					var entry = new ArchiveEntry(decodeRar4Name(header.sub(nameOffset, nameLength), flags & 0x200 != 0));
					entry.directory = flags & 0xE0 == 0xE0;
					entry.method = header.get(25);
					entry.crc = header.getInt32(16);
					entry.offset = position + headerSize;

					if (flags & 0x03 != 0)
						entry.unsupportedReason = "multi-volume RAR archives are not supported";
					else if (flags & 0x04 != 0)
						entry.unsupportedReason = "encrypted entries are not supported";
					else if (packedSize > MAX_INT || size > MAX_INT)
						entry.unsupportedReason = "entries larger than 2 GB are not supported";
					else if (!entry.directory && entry.method != RAR4_STORE)
						entry.unsupportedReason = COMPRESSED_MESSAGE;

					entry.packedSize = packedSize > MAX_INT ? 0 : Std.int(packedSize);
					entry.size = size > MAX_INT ? 0 : Std.int(size);

					if (entry.supported && entry.packedSize != entry.size)
						entry.unsupportedReason = COMPRESSED_MESSAGE;

					addEntry(entry);
				}
			}
			else if (flags & 0x8000 != 0)
			{
				if (headerSize < 11)
					throw new ArchiveException('"$name" has a corrupted block header');

				dataSize = unsigned(header.getInt32(7));
			}

			if (type == RAR4_MAIN && flags & 0x80 != 0)
				throw new ArchiveException('"$name" has encrypted headers, which are not supported');

			if (type == RAR4_END)
				break;

			var next = position + headerSize + dataSize;

			if (next > source.length)
				throw new ArchiveException('"$name" is truncated');

			position = Std.int(next);
		}
	}

	function parseRar5():Void
	{
		var position = 8;

		while (position + 5 <= source.length)
		{
			var prefixLength = source.length - position < 7 ? source.length - position : 7;
			var prefix = source.read(position, prefixLength);
			var crc = prefix.getInt32(0);
			var reader = new VIntReader(prefix, 4);
			var headerSize = reader.readInt();
			var headerStart = position + reader.position;

			if (headerSize <= 0 || headerStart + headerSize > source.length)
				throw new ArchiveException('"$name" has a corrupted block header');

			var checked = source.read(position + 4, reader.position - 4 + headerSize);

			if (haxe.crypto.Crc32.make(checked) != crc)
				throw new ArchiveException('"$name" has a block header with a bad checksum');

			var header = source.read(headerStart, headerSize);
			reader = new VIntReader(header, 0);

			var type = reader.readInt();
			var flags = reader.readInt();
			var extraSize = flags & 0x01 != 0 ? reader.readInt() : 0;
			var dataSize:Float = flags & 0x02 != 0 ? reader.read() : 0;
			var dataOffset = headerStart + headerSize;

			switch (type)
			{
				case RAR5_ENCRYPTION:
					throw new ArchiveException('"$name" has encrypted headers, which are not supported');

				case RAR5_FILE:
					var fileFlags = reader.readInt();
					var size = reader.read();
					reader.read();

					if (fileFlags & 0x02 != 0)
						reader.skip(4);

					var entryCrc:Null<Int> = null;

					if (fileFlags & 0x04 != 0)
					{
						entryCrc = header.getInt32(reader.position);
						reader.skip(4);
					}

					var compression = reader.readInt();
					reader.read();
					var nameLength = reader.readInt();

					if (reader.position + nameLength > header.length)
						throw new ArchiveException('"$name" has a corrupted file name');

					var entry = new ArchiveEntry(header.getString(reader.position, nameLength));
					entry.directory = fileFlags & 0x01 != 0;
					entry.method = (compression >> 7) & 0x07;
					entry.crc = entryCrc;
					entry.offset = dataOffset;

					if (flags & 0x18 != 0)
						entry.unsupportedReason = "multi-volume RAR archives are not supported";
					else if (hasRar5Record(header, extraSize, 0x01))
						entry.unsupportedReason = "encrypted entries are not supported";
					else if (dataSize > MAX_INT || size > MAX_INT)
						entry.unsupportedReason = "entries larger than 2 GB are not supported";
					else if (!entry.directory && entry.method != RAR5_STORE)
						entry.unsupportedReason = COMPRESSED_MESSAGE;

					entry.packedSize = dataSize > MAX_INT ? 0 : Std.int(dataSize);
					entry.size = size > MAX_INT ? 0 : Std.int(size);

					if (entry.supported && entry.packedSize != entry.size)
						entry.unsupportedReason = COMPRESSED_MESSAGE;

					if (!hasRar5Record(header, extraSize, 0x05))
						addEntry(entry);

				case RAR5_END:
					break;

				default:
			}

			var next = dataOffset + dataSize;

			if (next > source.length)
				throw new ArchiveException('"$name" is truncated');

			position = Std.int(next);
		}
	}

	static function isRar4Link(header:Bytes):Bool
	{
		var hostOs = header.get(15);
		var attributes = header.getInt32(28);

		if (hostOs == 3)
			return (attributes >> 12) & 0xF == 0xA;

		if (hostOs == 2)
			return attributes & 0x400 != 0;

		return false;
	}

	static function hasRar5Record(header:Bytes, extraSize:Int, recordType:Int):Bool
	{
		if (extraSize <= 0 || extraSize > header.length)
			return false;

		var reader = new VIntReader(header, header.length - extraSize);

		while (reader.position < header.length)
		{
			var recordSize = reader.readInt();
			var recordStart = reader.position;

			if (recordSize <= 0 || recordStart + recordSize > header.length)
				return false;

			if (reader.readInt() == recordType)
				return true;

			reader.position = recordStart + recordSize;
		}

		return false;
	}

	static function decodeRar4Name(bytes:Bytes, unicode:Bool):String
	{
		var zero = -1;

		for (i in 0...bytes.length)
			if (bytes.get(i) == 0)
			{
				zero = i;
				break;
			}

		if (!unicode)
			return bytes.getString(0, zero == -1 ? bytes.length : zero);

		if (zero == -1)
			return bytes.getString(0, bytes.length);

		var ascii = bytes.sub(0, zero);
		var encoded = bytes.sub(zero + 1, bytes.length - zero - 1);

		if (encoded.length == 0)
			return ascii.getString(0, ascii.length);

		var units:Array<Int> = [];
		var position = 0;
		var highByte = encoded.get(position++);
		var flags = 0;
		var flagBits = 0;
		var maxLength = ascii.length;

		while (position < encoded.length)
		{
			if (flagBits == 0)
			{
				flags = encoded.get(position++);
				flagBits = 8;
			}

			switch (flags >> 6)
			{
				case 0:
					if (position >= encoded.length)
						break;
					units.push(encoded.get(position++));
				case 1:
					if (position >= encoded.length)
						break;
					units.push(encoded.get(position++) + (highByte << 8));
				case 2:
					if (position + 1 >= encoded.length)
						break;
					units.push(encoded.get(position) + (encoded.get(position + 1) << 8));
					position += 2;
				default:
					if (position >= encoded.length)
						break;

					var length = encoded.get(position++);

					if (length & 0x80 != 0)
					{
						if (position >= encoded.length)
							break;

						var correction = encoded.get(position++);
						var count = (length & 0x7F) + 2;

						while (count > 0 && units.length < maxLength)
						{
							units.push(((ascii.get(units.length) + correction) & 0xFF) + (highByte << 8));
							count--;
						}
					}
					else
					{
						var count = length + 2;

						while (count > 0 && units.length < maxLength)
						{
							units.push(ascii.get(units.length));
							count--;
						}
					}
			}

			flags = (flags << 2) & 0xFF;
			flagBits -= 2;
		}

		var result = new StringBuf();
		var i = 0;

		while (i < units.length)
		{
			var unit = units[i];

			if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units.length && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF)
			{
				result.addChar(0x10000 + ((unit - 0xD800) << 10) + (units[i + 1] - 0xDC00));
				i += 2;
			}
			else
			{
				result.addChar(unit);
				i++;
			}
		}

		return result.toString();
	}

	static inline function unsigned(value:Int):Float
	{
		return value < 0 ? value + 4294967296.0 : value;
	}
}

private class VIntReader
{
	public var position:Int;

	var bytes:Bytes;

	public function new(bytes:Bytes, position:Int)
	{
		this.bytes = bytes;
		this.position = position;
	}

	public function read():Float
	{
		var result:Float = 0;
		var multiplier:Float = 1;

		for (i in 0...10)
		{
			if (position >= bytes.length)
				throw new ArchiveException("Unexpected end of RAR header");

			var byte = bytes.get(position++);
			result += (byte & 0x7F) * multiplier;
			multiplier *= 128;

			if (byte & 0x80 == 0)
				return result;
		}

		throw new ArchiveException("Invalid variable length integer in RAR header");
	}

	public function readInt():Int
	{
		var value = read();

		if (value > 2147483647)
			throw new ArchiveException("RAR header value is too large");

		return Std.int(value);
	}

	public function skip(count:Int):Void
	{
		position += count;
	}
}
