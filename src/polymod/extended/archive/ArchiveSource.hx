package polymod.extended.archive;

import haxe.io.Bytes;

interface IArchiveSource
{
	public var length(default, null):Int;

	public function read(position:Int, length:Int):Bytes;

	public function close():Void;
}

class BytesArchiveSource implements IArchiveSource
{
	public var length(default, null):Int;

	var bytes:Bytes;

	public function new(bytes:Bytes)
	{
		this.bytes = bytes;
		this.length = bytes.length;
	}

	public function read(position:Int, length:Int):Bytes
	{
		if (position < 0 || length < 0 || position + length > this.length)
			throw new ArchiveException('Read out of bounds (position $position, length $length, size ${this.length})');

		return bytes.sub(position, length);
	}

	public function close():Void {}
}

#if sys
class FileArchiveSource implements IArchiveSource
{
	public var length(default, null):Int;

	public var path(default, null):String;

	public function new(path:String)
	{
		this.path = path;
		this.length = sys.FileSystem.stat(path).size;
	}

	public function read(position:Int, length:Int):Bytes
	{
		if (position < 0 || length < 0 || position + length > this.length)
			throw new ArchiveException('Read out of bounds (position $position, length $length, size ${this.length})');

		var input = sys.io.File.read(path, true);

		try
		{
			input.seek(position, SeekBegin);
			var result = Bytes.alloc(length);
			var offset = 0;

			while (offset < length)
			{
				var count = input.readBytes(result, offset, length - offset);

				if (count <= 0)
					throw new ArchiveException('Unexpected end of file in "$path"');

				offset += count;
			}

			input.close();
			return result;
		}
		catch (e:haxe.io.Eof)
		{
			input.close();
			throw new ArchiveException('Unexpected end of file in "$path"');
		}
		catch (e:Dynamic)
		{
			input.close();
			throw e;
		}
	}

	public function close():Void {}
}
#end
