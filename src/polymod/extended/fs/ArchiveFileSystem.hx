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

	public var extraRoots(default, null):Array<String>;

	var archiveFiles:Map<String, String> = [];
	var archivePaths:Map<String, String> = [];
	var links:Map<String, String> = [];
	var linkKeys:Array<String> = [];

	public function new(params:PolymodFileSystemParams, ?extraRoots:Array<String>)
	{
		super(params);
		this.extraRoots = extraRoots != null ? extraRoots.copy() : [];
		archives = new ArchiveMounts(modRoot);
		archives.folderExists = realFolderExists;
		refresh();
	}

	public function setExtraRoots(roots:Array<String>):Void
	{
		extraRoots = roots != null ? roots.copy() : [];
		refresh();
	}

	public function refresh():Void
	{
		archives.unmountAll();
		archiveFiles = [];
		archivePaths = [];
		links = [];
		linkKeys = [];

		scanRoot(modRoot, true);

		for (root in extraRoots)
			if (root != null && ArchiveMounts.normalize(root) != ArchiveMounts.normalize(modRoot))
				scanRoot(root, false);

		archives.restoreMemoryArchives();
	}

	public function realPath(path:String):String
	{
		return translate(path);
	}

	public function isLinked(path:String):Bool
	{
		return translate(path) != path;
	}

	function scanRoot(root:String, primary:Bool):Void
	{
		if (!sys.FileSystem.exists(root) || !sys.FileSystem.isDirectory(root))
			return;

		var names = sys.FileSystem.readDirectory(root);
		names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		for (name in names)
		{
			var path = Path.join([root, name]);

			if (!sys.FileSystem.isDirectory(path))
			{
				if (ArchiveFormats.isArchivePath(name))
					mountFile(path);

				continue;
			}

			if (StringTools.startsWith(name, "."))
				continue;

			var isMod = sys.FileSystem.exists(Path.join([path, PolymodConfig.modMetadataFile]));

			if (!primary)
			{
				if (isMod || !primaryHas(name))
				{
					link(name, path);

					if (isMod)
						continue;
				}
				else
				{
					for (child in sortedChildren(path))
						if (sys.FileSystem.isDirectory(Path.join([path, child])) && !StringTools.startsWith(child, "."))
							link(name + "/" + child, Path.join([path, child]));
				}
			}
			else if (isMod)
				continue;

			for (child in sortedChildren(path))
			{
				var childPath = Path.join([path, child]);

				if (!sys.FileSystem.isDirectory(childPath) && ArchiveFormats.isArchivePath(child))
					mountFile(childPath, name + "/" + ArchiveMounts.defaultDirName(child));
			}
		}
	}

	function link(relative:String, real:String):Void
	{
		var virtual = ArchiveMounts.join(archives.root, relative);

		if (links.exists(virtual) || archives.isMounted(relative) || primaryHas(relative))
		{
			Polymod.warning(ARCHIVE_CONFLICT, 'Skipping "$real" because a mod folder named "$relative" already exists', SCAN);
			return;
		}

		links.set(virtual, real);
		linkKeys.push(virtual);
		linkKeys.sort((a, b) -> b.length - a.length);
	}

	function primaryHas(relative:String):Bool
	{
		var path = Path.join([modRoot, relative]);
		return sys.FileSystem.exists(path);
	}

	function translate(path:String):String
	{
		if (linkKeys.length == 0)
			return path;

		var key = ArchiveMounts.normalize(path);

		for (linkKey in linkKeys)
			if (key == linkKey || StringTools.startsWith(key, linkKey + "/"))
				return links.get(linkKey) + key.substr(linkKey.length);

		return path;
	}

	function linkChildren(path:String):Array<String>
	{
		var key = ArchiveMounts.normalize(path);
		var result:Array<String> = [];

		for (linkKey in linkKeys)
			if (ArchiveMounts.parentOf(linkKey) == key)
				result.push(linkKey.substr(key.length + (key.length > 0 ? 1 : 0)));

		return result;
	}

	static function sortedChildren(path:String):Array<String>
	{
		var children = sys.FileSystem.readDirectory(path);
		children.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return children;
	}

	public function mountFile(path:String, ?dirName:String):Bool
	{
		var name = Path.withoutDirectory(path);

		if (dirName == null)
			dirName = ArchiveMounts.defaultDirName(name);

		var parent = ArchiveMounts.parentOf(ArchiveMounts.normalize(dirName));
		var key = parent.length > 0 ? parent + "/" + name : name;
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

		if (links.exists(ArchiveMounts.join(archives.root, ArchiveMounts.normalize(dirName))))
		{
			Polymod.warning(ARCHIVE_CONFLICT, 'Skipping "${archive.name}" because a mod folder named "$dirName" already exists', SCAN);
			archive.close();
			return false;
		}

		if (!archives.mount(archive, dirName))
			return false;

		archiveFiles.set(key, dirName);
		archivePaths.set(ArchiveMounts.normalize(dirName), path);
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

		archivePaths.remove(ArchiveMounts.normalize(dirName));
		return archives.unmount(dirName);
	}

	public function unmountAll():Void
	{
		archiveFiles = [];
		archivePaths = [];
		archives.unmountAll(true);
	}

	public function isMounted(dirName:String):Bool
	{
		return archives.isMounted(dirName);
	}

	public function getArchiveFile(dirName:String):Null<String>
	{
		return archivePaths.get(ArchiveMounts.normalize(dirName));
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
		if (archives.hasFile(path) || archives.hasDirectory(path))
			return true;

		var real = translate(path);
		return super.exists(real) || links.exists(ArchiveMounts.normalize(path));
	}

	function rawIsDirectory(path:String):Bool
	{
		if (archives.hasDirectory(path))
			return true;

		if (archives.hasFile(path))
			return false;

		var real = translate(path);
		return super.exists(real) && super.isDirectory(real);
	}

	function rawReadDirectory(path:String):Array<String>
	{
		var mounted = archives.readDirectory(path);
		var real = translate(path);
		var isReal = super.exists(real) && super.isDirectory(real);
		var linked = linkChildren(path);

		if (mounted == null && linked.length == 0)
			return super.readDirectory(real);

		var result = isReal ? super.readDirectory(real) : [];
		var relative = relativeToRoot(path);

		if (relative != null)
			result = result.filter(name -> !archiveFiles.exists(relative.length > 0 ? relative + "/" + name : name));

		for (child in linked.concat(mounted != null ? mounted : []))
			if (!result.contains(child))
				result.push(child);

		return result;
	}

	function rawGetFileBytes(path:String):Bytes
	{
		if (archives.hasFile(path))
			return archives.readBytes(path);

		return super.getFileBytes(translate(path));
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
		var real = translate(path);
		return (super.exists(real) && super.isDirectory(real)) || links.exists(ArchiveMounts.normalize(path));
	}

	function get_mounts():Map<String, Archive>
	{
		return archives.mounts;
	}
}
#end
