package polymod.extended.archive;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.extended.archive.ArchiveSource;

typedef ArchiveFormat =
{
	name:String,
	extensions:Array<String>,
	detect:Bytes->Bool,
	open:(IArchiveSource, String) -> Archive
}

class ArchiveFormats
{
	public static inline final HEADER_SIZE:Int = 16;

	public static var formats(default, null):Array<ArchiveFormat> = [
		{
			name: "zip",
			extensions: ["zip"],
			detect: ZipArchive.isZip,
			open: (source, name) -> new ZipArchive(source, name)
		},
		{
			name: "rar",
			extensions: ["rar"],
			detect: RarArchive.isRar,
			open: (source, name) -> new RarArchive(source, name)
		}
	];

	public static function register(format:ArchiveFormat):Void
	{
		unregister(format.name);
		formats.push(format);
	}

	public static function unregister(name:String):Void
	{
		formats = formats.filter(format -> format.name != name);
	}

	public static function getByExtension(path:String):Null<ArchiveFormat>
	{
		var extension = Path.extension(path).toLowerCase();

		if (extension.length == 0)
			return null;

		for (format in formats)
			if (format.extensions.contains(extension))
				return format;

		return null;
	}

	public static function isArchivePath(path:String):Bool
	{
		return getByExtension(path) != null;
	}

	public static function open(source:IArchiveSource, name:String):Archive
	{
		var header = source.read(0, source.length < HEADER_SIZE ? source.length : HEADER_SIZE);

		for (format in formats)
			if (format.detect(header))
				return format.open(source, name);

		var format = getByExtension(name);

		if (format != null)
			throw new ArchiveException('"$name" is not a valid ${format.name} file');

		throw new ArchiveException('"$name" is not a supported archive');
	}

	public static function openBytes(bytes:Bytes, name:String):Archive
	{
		return open(new BytesArchiveSource(bytes), name);
	}

	#if sys
	public static function openFile(path:String):Archive
	{
		return open(new FileArchiveSource(path), Path.withoutDirectory(path));
	}
	#end
}
