package polymod.extended.fs;

#if sys
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.PolymodConfig;
import polymod.extended.archive.Archive;
import polymod.extended.archive.ArchiveFormats;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
import polymod.extended.structure.FolderMapper;
import polymod.fs.SysFileSystem;

class ArchiveFileSystem extends SysFileSystem implements IFolderMapping
{
	public static inline final ARCHIVE_OPEN_FAILED:PolymodErrorCode = ArchiveMounts.ARCHIVE_OPEN_FAILED;
	public static inline final ARCHIVE_UNSUPPORTED:PolymodErrorCode = ArchiveMounts.ARCHIVE_UNSUPPORTED;
	public static inline final ARCHIVE_CONFLICT:PolymodErrorCode = ArchiveMounts.ARCHIVE_CONFLICT;
	public static inline final ARCHIVE_READ_FAILED:PolymodErrorCode = ArchiveMounts.ARCHIVE_READ_FAILED;
	public static inline final ARCHIVE_MOUNTED:PolymodErrorCode = ArchiveMounts.ARCHIVE_MOUNTED;

	public var archives(default, null):ArchiveMounts;

	public var mounts(get, never):Map<String, Archive>;

	public var mapper(default, null):FolderMapper = new FolderMapper();

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

			if (!sys.FileSystem.isDirectory(path))
			{
				if (ArchiveFormats.isArchivePath(name))
					mountFile(path);

				continue;
			}

			if (sys.FileSystem.exists(Path.join([path, PolymodConfig.modMetadataFile])))
				continue;

			var children = sys.FileSystem.readDirectory(path);
			children.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			for (child in children)
			{
				var childPath = Path.join([path, child]);

				if (!sys.FileSystem.isDirectory(childPath) && ArchiveFormats.isArchivePath(child))
					mountFile(childPath, name + "/" + ArchiveMounts.defaultDirName(child));
			}
		}

		archives.restoreMemoryArchives();
	}

	public function mountFile(path:String, ?dirName:String):Bool
	{
		var name = Path.withoutDirectory(path);
		var key = relativeToRoot(path);

		if (key == null)
			key = name;

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

		archiveFiles.set(key, dirName);
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
		return rawExists(path) || (mapper.hasMappings() && (mapper.resolve(path, rawExists) != null || mappedDirectory(path)));
	}

	override public function isDirectory(path:String):Bool
	{
		if (rawIsDirectory(path))
			return true;

		if (!mapper.hasMappings() || rawExists(path))
			return false;

		var resolved = mapper.resolve(path, rawExists);
		return resolved != null ? rawIsDirectory(resolved) : mappedDirectory(path);
	}

	override public function readDirectory(path:String):Array<String>
	{
		var result = rawIsDirectory(path) ? rawReadDirectory(path) : [];

		if (mapper.hasMappings())
		{
			for (child in mapper.children(path, rawIsDirectory, rawReadDirectory))
				if (!result.contains(child))
					result.push(child);
		}
		else if (result.length == 0 && !rawIsDirectory(path))
			return rawReadDirectory(path);

		return result;
	}

	override public function getFileBytes(path:String):Bytes
	{
		if (!rawExists(path) && mapper.hasMappings())
		{
			var resolved = mapper.resolve(path, rawExists);

			if (resolved != null)
				return rawGetFileBytes(resolved);
		}

		return rawGetFileBytes(path);
	}

	override public function getFileContent(path:String):String
	{
		var bytes = getFileBytes(path);
		return bytes != null ? bytes.toString() : null;
	}

	function mappedDirectory(path:String):Bool
	{
		return mapper.isDirectory(path, rawIsDirectory, rawReadDirectory);
	}

	function rawExists(path:String):Bool
	{
		return archives.hasFile(path) || archives.hasDirectory(path) || super.exists(path);
	}

	function rawIsDirectory(path:String):Bool
	{
		if (archives.hasDirectory(path))
			return true;

		if (archives.hasFile(path))
			return false;

		return super.exists(path) && super.isDirectory(path);
	}

	function rawReadDirectory(path:String):Array<String>
	{
		var mounted = archives.readDirectory(path);
		var real = super.exists(path) && super.isDirectory(path);

		if (mounted == null)
			return super.readDirectory(path);

		var result = real ? super.readDirectory(path) : [];
		var relative = relativeToRoot(path);

		if (relative != null)
			result = result.filter(name -> !archiveFiles.exists(relative.length > 0 ? relative + "/" + name : name));

		for (child in mounted)
			if (!result.contains(child))
				result.push(child);

		return result;
	}

	function rawGetFileBytes(path:String):Bytes
	{
		if (archives.hasFile(path))
			return archives.readBytes(path);

		return super.getFileBytes(path);
	}

	function relativeToRoot(path:String):Null<String>
	{
		var key = ArchiveMounts.normalize(path);
		var root = archives.root;

		if (key == root)
			return "";

		if (root.length == 0)
			return key;

		return StringTools.startsWith(key, root + "/") ? key.substr(root.length + 1) : null;
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
