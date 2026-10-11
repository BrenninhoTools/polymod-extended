package polymod.extended.images;

import haxe.io.Bytes;

enum abstract ImageType(String) from String to String
{
	var PNG = "png";
	var JPEG = "jpeg";
	var GIF = "gif";
	var WEBP = "webp";
	var UNKNOWN = "unknown";
}

class ImageInfo
{
	public var type(default, null):ImageType;

	public var width(default, null):Int;

	public var height(default, null):Int;

	public var hasAlpha(default, null):Bool;

	public function new(type:ImageType, width:Int, height:Int, hasAlpha:Bool)
	{
		this.type = type;
		this.width = width;
		this.height = height;
		this.hasAlpha = hasAlpha;
	}

	public static function read(bytes:Bytes):Null<ImageInfo>
	{
		if (bytes == null || bytes.length < 12)
			return null;

		if (isPng(bytes))
			return readPng(bytes);

		if (bytes.get(0) == 0xFF && bytes.get(1) == 0xD8)
			return readJpeg(bytes);

		if (bytes.getString(0, 3) == "GIF" && bytes.length >= 10)
			return new ImageInfo(GIF, bytes.getUInt16(6), bytes.getUInt16(8), true);

		if (bytes.getString(0, 4) == "RIFF" && bytes.length >= 30 && bytes.getString(8, 4) == "WEBP")
			return readWebp(bytes);

		return null;
	}

	public static function isPng(bytes:Bytes):Bool
	{
		return bytes != null && bytes.length >= 8 && bytes.get(0) == 0x89 && bytes.get(1) == 0x50 && bytes.get(2) == 0x4E && bytes.get(3) == 0x47
			&& bytes.get(4) == 0x0D && bytes.get(5) == 0x0A && bytes.get(6) == 0x1A && bytes.get(7) == 0x0A;
	}

	public static function isPowerOfTwo(value:Int):Bool
	{
		return value > 0 && (value & (value - 1)) == 0;
	}

	static function readPng(bytes:Bytes):Null<ImageInfo>
	{
		if (bytes.length < 26 || bytes.getString(12, 4) != "IHDR")
			return null;

		var colorType = bytes.get(25);
		var alpha = colorType == 4 || colorType == 6;

		if (!alpha && colorType == 3)
		{
			var position = 8;

			while (position + 8 <= bytes.length)
			{
				var length = bigEndian(bytes, position);
				var chunk = bytes.getString(position + 4, 4);

				if (chunk == "tRNS")
				{
					alpha = true;
					break;
				}

				if (chunk == "IDAT" || chunk == "IEND" || length < 0)
					break;

				position += 12 + length;
			}
		}

		return new ImageInfo(PNG, bigEndian(bytes, 16), bigEndian(bytes, 20), alpha);
	}

	static function readJpeg(bytes:Bytes):Null<ImageInfo>
	{
		var position = 2;

		while (position + 9 < bytes.length)
		{
			if (bytes.get(position) != 0xFF)
			{
				position++;
				continue;
			}

			var marker = bytes.get(position + 1);

			if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7))
			{
				position += 2;
				continue;
			}

			var length = (bytes.get(position + 2) << 8) | bytes.get(position + 3);

			if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC)
			{
				var height = (bytes.get(position + 5) << 8) | bytes.get(position + 6);
				var width = (bytes.get(position + 7) << 8) | bytes.get(position + 8);
				return new ImageInfo(JPEG, width, height, false);
			}

			position += 2 + length;
		}

		return null;
	}

	static function readWebp(bytes:Bytes):Null<ImageInfo>
	{
		var chunk = bytes.getString(12, 4);

		if (chunk == "VP8X")
			return new ImageInfo(WEBP, 1 + (bytes.get(24) | (bytes.get(25) << 8) | (bytes.get(26) << 16)),
				1 + (bytes.get(27) | (bytes.get(28) << 8) | (bytes.get(29) << 16)), (bytes.get(20) & 0x10) != 0);

		if (chunk == "VP8L" && bytes.length >= 25)
		{
			var bits = bytes.get(21) | (bytes.get(22) << 8) | (bytes.get(23) << 16) | (bytes.get(24) << 24);
			return new ImageInfo(WEBP, 1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF), true);
		}

		if (chunk == "VP8 " && bytes.length >= 30)
			return new ImageInfo(WEBP, bytes.getUInt16(26) & 0x3FFF, bytes.getUInt16(28) & 0x3FFF, false);

		return null;
	}

	static inline function bigEndian(bytes:Bytes, position:Int):Int
	{
		return (bytes.get(position) << 24) | (bytes.get(position + 1) << 16) | (bytes.get(position + 2) << 8) | bytes.get(position + 3);
	}
}
