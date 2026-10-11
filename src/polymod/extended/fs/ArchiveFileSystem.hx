package polymod.extended.fs;

#if sys
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.extended.archive.Archive;
import polymod.extended.archive.ArchiveFormats;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
import polymod.fs.SysFileSystem;

class ArchiveFileSystem extends SysFileSystem
{
	public static inline final ARCHIVE_OPEN_FAILED:PolymodErrorCode = ArchiveMounts.ARCHIVE_OPEN_FAILED;
	public static inline final ARCHIVE_UNSUPPORTED:PolymodErrorCode = ArchiveMounts.ARCHIVE_UNSUPPORTED;
	public static inline final ARCHIVE_CONFLICT:PolymodErrorCode = ArchiveMounts.ARCHIVE_CONFLICT;
	public static inline final ARCHIVE_READ_FAILED:PolymodErrorCode = ArchiveMounts.ARCHIVE_READ_FAILED;
	public static inline final ARCHIVE_MOUNTED:PolymodErrorCode = ArchiveMounts.ARCHIVE_MOUNTED;

	public var archives(default, null):ArchiveMounts;

	public var mounts(get, never):Map<String, Archive>;

	var archiveFiles:Map<String, String> = [];

	public function new(params:PolymodFileSystemParams)
	{
		super(params);
		archives = new ArchiveMounts(modRoot);
		archives.folderExists = realFolderExists;
		refresh();
	}

	public function refresh():Void
	{
		archives.unmountAll();
		archiveFiles = [];

		var names = sys.FileSystem.exists(modRoot) && sys.FileSystem.isDirectory(modRoot) ? sys.FileSystem.readDirectory(modRoot) : [];
		names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		for (name in names)
		{
			var path = Path.join([modRoot, name]);

			if (!sys.FileSystem.isDirectory(path) && ArchiveFormats.isArchivePath(name))
				mountFile(path);
		}

		archives.restoreMemoryArchives();
	}

	public function mountFile(path:String, ?dirName:String):Bool
	{
		var name = Path.withoutDirectory(path);

		if (dirName == null)
			dirName = ArchiveMounts.defaultDirName(name);

		var archive:Archive;

		try
		{
			archive = ArchiveFormats.openFile(path);
		}
		catch (e:Dynamic)
		{
			Polymod.error(ARCHIVE_OPEN_FAILED, 'Could not open "$name": ${ArchiveMounts.message(e)}', SCAN);
			return false;
		}

		if (!archives.mount(archive, dirName))
			return false;

		archiveFiles.set(name, dirName);
		return true;
	}

	public function mountBytes(bytes:Bytes, name:String, ?dirName:String):Bool
	{
		return archives.mountBytes(bytes, name, dirName);
	}

	public function mount(archive:Archive, dirName:String):Bool
	{
		return archives.mount(archive, dirName);
	}

	public function unmount(dirName:String):Bool
	{
		for (name in [for (name => mounted in archiveFiles) if (mounted == dirName) name])
			archiveFiles.remove(name);

		return archives.unmount(dirName);
	}

	public function unmountAll():Void
	{
		archiveFiles = [];
		archives.unmountAll(true);
	}

	public function isMounted(dirName:String):Bool
	{
		return archives.isMounted(dirName);
	}

	public function getArchiveFile(dirName:String):Null<String>
	{
		for (name => mounted in archiveFiles)
			if (mounted == dirName)
				return Path.join([modRoot, name]);

		return null;
	}

	override public function exists(path:String):Bool
	{
		if (archives.hasFile(path) || archives.hasDirectory(path))
			return true;

		return super.exists(path);
	}

	override public function isDirectory(path:String):Bool
	{
		if (archives.hasDirectory(path))
			return true;

		if (archives.hasFile(path))
			return false;

		return super.exists(path) && super.isDirectory(path);
	}

	override public function readDirectory(path:String):Array<String>
	{
		var mounted = archives.readDirectory(path);
		var real = super.exists(path) && super.isDirectory(path);

		if (mounted == null)
			return super.readDirectory(path);

		var result = real ? super.readDirectory(path) : [];

		if (ArchiveMounts.normalize(path) == archives.root)
			result = result.filter(name -> !archiveFiles.exists(name));

		for (child in mounted)
			if (!result.contains(child))
				result.push(child);

		return result;
	}

	override public function getFileBytes(path:String):Bytes
	{
		if (archives.hasFile(path))
			return archives.readBytes(path);

		return super.getFileBytes(path);
	}

	override public function getFileContent(path:String):String
	{
		var bytes = getFileBytes(path);
		return bytes != null ? bytes.toString() : null;
	}

	function realFolderExists(path:String):Bool
	{
		return super.exists(path) && super.isDirectory(path);
	}

	function get_mounts():Map<String, Archive>
	{
		return archives.mounts;
	}
}
#end
