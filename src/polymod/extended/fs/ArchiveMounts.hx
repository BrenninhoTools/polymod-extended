package polymod.extended.fs;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.PolymodConfig;
import polymod.extended.archive.Archive;
import polymod.extended.archive.ArchiveFormats;

typedef MountedFile =
{
	archive:Archive,
	entry:String
}

typedef MemoryArchive =
{
	bytes:Bytes,
	name:String,
	dirName:String
}

class ArchiveMounts
{
	public static inline final ARCHIVE_OPEN_FAILED:PolymodErrorCode = "archive_open_failed";
	public static inline final ARCHIVE_UNSUPPORTED:PolymodErrorCode = "archive_unsupported";
	public static inline final ARCHIVE_CONFLICT:PolymodErrorCode = "archive_conflict";
	public static inline final ARCHIVE_READ_FAILED:PolymodErrorCode = "archive_read_failed";
	public static inline final ARCHIVE_MOUNTED:PolymodErrorCode = "archive_mounted";

	public static var ignoredPrefixes:Array<String> = ["__MACOSX/"];

	public static var ignoredNames:Array<String> = [".DS_Store", "Thumbs.db", "desktop.ini"];

	public var root(default, null):String;

	public var mounts(default, null):Map<String, Archive> = [];

	public var memoryArchives(default, null):Array<MemoryArchive> = [];

	public var folderExists:String->Bool = null;

	var files:Map<String, MountedFile> = [];
	var lowerFiles:Map<String, MountedFile> = [];
	var directories:Map<String, Array<String>> = [];
	var lowerDirectories:Map<String, String> = [];

	public function new(modRoot:String)
	{
		root = normalize(modRoot);
	}

	public function mountBytes(bytes:Bytes, name:String, ?dirName:String, remember:Bool = true):Bool
	{
		if (dirName == null)
			dirName = defaultDirName(name);

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

		if (!mount(archive, dirName))
			return false;

		if (remember)
		{
			memoryArchives = memoryArchives.filter(memory -> memory.dirName != dirName);
			memoryArchives.push({bytes: bytes, name: name, dirName: dirName});
		}

		return true;
	}

	public function restoreMemoryArchives():Void
	{
		for (memory in memoryArchives.copy())
			if (!mounts.exists(memory.dirName) && !mountBytes(memory.bytes, memory.name, memory.dirName, false))
				memoryArchives.remove(memory);
	}

	public function mount(archive:Archive, dirName:String):Bool
	{
		var modDir = Archive.normalizePath(dirName);

		if (modDir == null || modDir.length == 0 || modDir.split("/").length > 2)
		{
			Polymod.error(ARCHIVE_CONFLICT, 'Invalid mod folder name "$dirName" for "${archive.name}"', SCAN);
			archive.close();
			return false;
		}

		if (mounts.exists(modDir) || (folderExists != null && folderExists(join(root, modDir))))
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
			var parent = parentOf(virtualPath);
			var mounted:MountedFile = {archive: archive, entry: entry.path};
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

	public function unmount(dirName:String, forget:Bool = true):Bool
	{
		if (forget)
			memoryArchives = memoryArchives.filter(memory -> memory.dirName != dirName);

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

		var current = base;

		while (current != root && current.length > root.length)
		{
			var parent = parentOf(current);
			var siblings = directories.get(parent);

			if (siblings == null)
				break;

			siblings.remove(current.substr(parent.length + (parent.length > 0 ? 1 : 0)));

			if (siblings.length > 0 || parent == root)
				break;

			directories.remove(parent);
			lowerDirectories.remove(parent.toLowerCase());
			current = parent;
		}

		mounts.remove(dirName);
		archive.close();
		return true;
	}

	public function unmountAll(forget:Bool = false):Void
	{
		for (archive in mounts)
			archive.close();

		if (forget)
			memoryArchives = [];

		mounts = [];
		files = [];
		lowerFiles = [];
		directories = [];
		lowerDirectories = [];
	}

	public function isMounted(dirName:String):Bool
	{
		return mounts.exists(dirName);
	}

	public function hasFile(path:String):Bool
	{
		return findFile(normalize(path)) != null;
	}

	public function hasDirectory(path:String):Bool
	{
		return findDirectory(normalize(path)) != null;
	}

	public function readDirectory(path:String):Null<Array<String>>
	{
		var directory = findDirectory(normalize(path));
		return directory != null ? directories.get(directory).copy() : null;
	}

	public function listFiles(path:String):Array<String>
	{
		var directory = findDirectory(normalize(path));

		if (directory == null)
			return [];

		var prefix = directory.length > 0 ? directory + "/" : "";
		return [for (key in files.keys()) if (StringTools.startsWith(key, prefix)) key.substr(prefix.length)];
	}

	public function readBytes(path:String):Null<Bytes>
	{
		var mounted = findFile(normalize(path));

		if (mounted == null)
			return null;

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

	function findFile(key:String):Null<MountedFile>
	{
		var mounted = files.get(key);
		return mounted != null ? mounted : lowerFiles.get(key.toLowerCase());
	}

	function findDirectory(key:String):Null<String>
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

	public static function defaultDirName(name:String):String
	{
		return Path.withoutExtension(Path.withoutDirectory(StringTools.replace(name, "\\", "/")));
	}

	public static function findContentPrefix(archive:Archive):String
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

	public static function isIgnored(path:String):Bool
	{
		for (prefix in ignoredPrefixes)
			if (StringTools.startsWith(path, prefix))
				return true;

		return ignoredNames.contains(Path.withoutDirectory(path));
	}

	public static function parentOf(path:String):String
	{
		var slash = path.lastIndexOf("/");

		if (slash == -1)
			return "";

		return slash == 0 ? "/" : path.substr(0, slash);
	}

	public static function join(a:String, b:String):String
	{
		if (a.length == 0)
			return b;

		return StringTools.endsWith(a, "/") ? a + b : a + "/" + b;
	}

	public static function normalize(path:String):String
	{
		if (path == null)
			return "";

		var unified = StringTools.replace(path, "\\", "/");
		var absolute = StringTools.startsWith(unified, "/");
		var parts = [for (part in unified.split("/")) if (part != "" && part != ".") part];
		var result = parts.join("/");
		return absolute ? "/" + result : result;
	}

	public static function message(e:Dynamic):String
	{
		if (Std.isOfType(e, haxe.Exception))
			return (e : haxe.Exception).message;

		return Std.string(e);
	}
}
