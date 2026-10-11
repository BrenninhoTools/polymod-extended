package polymod.extended.fs;

#if sys
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.PolymodConfig;
import polymod.extended.archive.Archive;
import polymod.extended.archive.ArchiveFormats;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
import polymod.fs.SysFileSystem;

typedef MountedFile =
{
	archive:Archive,
	entry:String
}

class ArchiveFileSystem extends SysFileSystem
{
	public static inline final ARCHIVE_OPEN_FAILED:PolymodErrorCode = "archive_open_failed";
	public static inline final ARCHIVE_UNSUPPORTED:PolymodErrorCode = "archive_unsupported";
	public static inline final ARCHIVE_CONFLICT:PolymodErrorCode = "archive_conflict";
	public static inline final ARCHIVE_READ_FAILED:PolymodErrorCode = "archive_read_failed";
	public static inline final ARCHIVE_MOUNTED:PolymodErrorCode = "archive_mounted";

	public static var ignoredPrefixes:Array<String> = ["__MACOSX/"];

	public static var ignoredNames:Array<String> = [".DS_Store", "Thumbs.db", "desktop.ini"];

	public var mounts(default, null):Map<String, Archive> = [];

	var archiveFiles:Map<String, String> = [];
	var memoryArchives:Array<{bytes:Bytes, name:String, dirName:String}> = [];
	var files:Map<String, MountedFile> = [];
	var lowerFiles:Map<String, MountedFile> = [];
	var directories:Map<String, Array<String>> = [];
	var lowerDirectories:Map<String, String> = [];
	var root:String;

	public function new(params:PolymodFileSystemParams)
	{
		super(params);
		root = normalize(modRoot);
		refresh();
	}

	public function refresh():Void
	{
		unmountAll();

		var names = sys.FileSystem.exists(modRoot) && sys.FileSystem.isDirectory(modRoot) ? sys.FileSystem.readDirectory(modRoot) : [];
		names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		for (name in names)
		{
			var path = Path.join([modRoot, name]);

			if (!sys.FileSystem.isDirectory(path) && ArchiveFormats.isArchivePath(name))
				mountFile(path);
		}

		for (memory in memoryArchives.copy())
			if (!mountMemory(memory.bytes, memory.name, memory.dirName))
				memoryArchives.remove(memory);
	}

	public function mountFile(path:String, ?dirName:String):Bool
	{
		var name = Path.withoutDirectory(path);

		if (dirName == null)
			dirName = Path.withoutExtension(name);

		var archive:Archive;

		try
		{
			archive = ArchiveFormats.openFile(path);
		}
		catch (e:Dynamic)
		{
			Polymod.error(ARCHIVE_OPEN_FAILED, 'Could not open "$name": ${message(e)}', SCAN);
			return false;
		}

		if (!mount(archive, dirName))
			return false;

		archiveFiles.set(name, dirName);
		return true;
	}

	public function mountBytes(bytes:Bytes, name:String, ?dirName:String):Bool
	{
		if (dirName == null)
			dirName = Path.withoutExtension(Path.withoutDirectory(name));

		if (!mountMemory(bytes, name, dirName))
			return false;

		memoryArchives.push({bytes: bytes, name: name, dirName: dirName});
		return true;
	}

	function mountMemory(bytes:Bytes, name:String, dirName:String):Bool
	{
		var archive:Archive;

		try
		{
			archive = ArchiveFormats.openBytes(bytes, name);
		}
		catch (e:Dynamic)
		{
			Polymod.error(ARCHIVE_OPEN_FAILED, 'Could not open "$name": ${message(e)}', SCAN);
			return false;
		}

		return mount(archive, dirName);
	}

	public function mount(archive:Archive, dirName:String):Bool
	{
		var modDir = Archive.normalizePath(dirName);

		if (modDir == null || modDir.length == 0 || modDir.indexOf("/") != -1)
		{
			Polymod.error(ARCHIVE_CONFLICT, 'Invalid mod folder name "$dirName" for "${archive.name}"', SCAN);
			archive.close();
			return false;
		}

		if (mounts.exists(modDir) || super.exists(Path.join([modRoot, modDir])))
		{
			Polymod.warning(ARCHIVE_CONFLICT, 'Skipping "${archive.name}" because a mod folder named "$modDir" already exists', SCAN);
			archive.close();
			return false;
		}

		var unsupported = archive.getUnsupportedEntries();

		if (unsupported.length > 0)
		{
			Polymod.error(ARCHIVE_UNSUPPORTED,
				'Skipping "${archive.name}": ${unsupported.length} file(s) cannot be read, ${unsupported[0].unsupportedReason}', SCAN);
			archive.close();
			return false;
		}

		var prefix = findContentPrefix(archive);
		var base = join(root, modDir);

		addDirectory(base);

		for (entry in archive.entries)
		{
			if (entry.directory || !StringTools.startsWith(entry.path, prefix) || isIgnored(entry.path))
				continue;

			var relative = entry.path.substr(prefix.length);

			if (relative.length == 0)
				continue;

			var virtualPath = join(base, relative);
			var mounted:MountedFile = {archive: archive, entry: entry.path};
			var parent = parentOf(virtualPath);
			files.set(virtualPath, mounted);
			lowerFiles.set(virtualPath.toLowerCase(), mounted);
			addDirectory(parent);

			var children = directories.get(parent);
			var fileName = virtualPath.substr(parent.length + 1);

			if (!children.contains(fileName))
				children.push(fileName);
		}

		mounts.set(modDir, archive);
		Polymod.info(ARCHIVE_MOUNTED, 'Mounted "${archive.name}" as "$modDir"', SCAN);
		return true;
	}

	public function unmount(dirName:String):Bool
	{
		var archive = mounts.get(dirName);

		if (archive == null)
			return false;

		var base = join(root, dirName);
		var prefix = base + "/";

		for (key in [for (key in files.keys()) key])
			if (StringTools.startsWith(key, prefix))
			{
				files.remove(key);
				lowerFiles.remove(key.toLowerCase());
			}

		for (key in [for (key in directories.keys()) key])
			if (key == base || StringTools.startsWith(key, prefix))
			{
				directories.remove(key);
				lowerDirectories.remove(key.toLowerCase());
			}

		var rootChildren = directories.get(root);

		if (rootChildren != null)
			rootChildren.remove(dirName);

		for (name in [for (name => mounted in archiveFiles) if (mounted == dirName) name])
			archiveFiles.remove(name);

		memoryArchives = memoryArchives.filter(memory -> memory.dirName != dirName);
		mounts.remove(dirName);
		archive.close();
		return true;
	}

	public function unmountAll():Void
	{
		for (archive in mounts)
			archive.close();

		mounts = [];
		archiveFiles = [];
		files = [];
		lowerFiles = [];
		directories = [];
		lowerDirectories = [];
	}

	public function isMounted(dirName:String):Bool
	{
		return mounts.exists(dirName);
	}

	override public function exists(path:String):Bool
	{
		var key = normalize(path);

		if (findMountedFile(key) != null || findMountedDirectory(key) != null)
			return true;

		return super.exists(path);
	}

	override public function isDirectory(path:String):Bool
	{
		var key = normalize(path);

		if (findMountedDirectory(key) != null)
			return true;

		if (findMountedFile(key) != null)
			return false;

		return super.exists(path) && super.isDirectory(path);
	}

	override public function readDirectory(path:String):Array<String>
	{
		var key = normalize(path);
		var directory = findMountedDirectory(key);
		var result:Array<String> = [];

		if (super.exists(path) && super.isDirectory(path))
			result = super.readDirectory(path);
		else if (directory == null)
			return super.readDirectory(path);

		if (directory == key && key == root)
			result = result.filter(name -> !archiveFiles.exists(name));

		if (directory != null)
			for (child in directories.get(directory))
				if (!result.contains(child))
					result.push(child);

		return result;
	}

	override public function getFileBytes(path:String):Bytes
	{
		var mounted = findMountedFile(normalize(path));

		if (mounted == null)
			return super.getFileBytes(path);

		try
		{
			return mounted.archive.read(mounted.entry);
		}
		catch (e:Dynamic)
		{
			Polymod.error(ARCHIVE_READ_FAILED, 'Could not read "${mounted.entry}" from "${mounted.archive.name}": ${message(e)}');
			return null;
		}
	}

	override public function getFileContent(path:String):String
	{
		var bytes = getFileBytes(path);
		return bytes != null ? bytes.toString() : null;
	}

	function findMountedFile(key:String):Null<MountedFile>
	{
		var mounted = files.get(key);
		return mounted != null ? mounted : lowerFiles.get(key.toLowerCase());
	}

	function findMountedDirectory(key:String):Null<String>
	{
		if (directories.exists(key))
			return key;

		return lowerDirectories.get(key.toLowerCase());
	}

	function addDirectory(path:String):Void
	{
		var current = path;

		while (current != root && current.length > root.length)
		{
			var parent = parentOf(current);

			if (!directories.exists(current))
			{
				directories.set(current, []);
				lowerDirectories.set(current.toLowerCase(), current);
			}

			if (!directories.exists(parent))
			{
				directories.set(parent, []);
				lowerDirectories.set(parent.toLowerCase(), parent);
			}

			var name = current.substr(parent.length + (parent.length > 0 ? 1 : 0));
			var children = directories.get(parent);

			if (children.contains(name))
				return;

			children.push(name);
			current = parent;
		}
	}

	static function findContentPrefix(archive:Archive):String
	{
		var metaFile = PolymodConfig.modMetadataFile;

		if (archive.has(metaFile))
			return "";

		var top:Null<String> = null;

		for (entry in archive.entries)
		{
			if (isIgnored(entry.path))
				continue;

			var slash = entry.path.indexOf("/");

			if (slash == -1)
			{
				if (!entry.directory)
					return "";

				continue;
			}

			var first = entry.path.substr(0, slash);

			if (top == null)
				top = first;
			else if (top != first)
				return "";
		}

		return top != null && archive.has(top + "/" + metaFile) ? top + "/" : "";
	}

	static function isIgnored(path:String):Bool
	{
		for (prefix in ignoredPrefixes)
			if (StringTools.startsWith(path, prefix))
				return true;

		return ignoredNames.contains(Path.withoutDirectory(path));
	}

	static function parentOf(path:String):String
	{
		var slash = path.lastIndexOf("/");

		if (slash == -1)
			return "";

		return slash == 0 ? "/" : path.substr(0, slash);
	}

	static function join(a:String, b:String):String
	{
		if (a.length == 0)
			return b;

		return StringTools.endsWith(a, "/") ? a + b : a + "/" + b;
	}

	static function normalize(path:String):String
	{
		if (path == null)
			return "";

		var unified = StringTools.replace(path, "\\", "/");
		var absolute = StringTools.startsWith(unified, "/");
		var parts = [for (part in unified.split("/")) if (part != "" && part != ".") part];
		var result = parts.join("/");
		return absolute ? "/" + result : result;
	}

	static function message(e:Dynamic):String
	{
		if (Std.isOfType(e, haxe.Exception))
			return (e : haxe.Exception).message;

		return Std.string(e);
	}
}
#end
