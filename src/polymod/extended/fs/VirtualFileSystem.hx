package polymod.extended.fs;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.PolymodConfig;
import polymod.extended.archive.Archive;
import polymod.fs.MemoryFileSystem;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
import polymod.util.Util;

class VirtualFileSystem extends MemoryFileSystem
{
	public var archives(default, null):ArchiveMounts;

	public var root(get, never):String;

	var looseFiles:Map<String, Bytes> = [];

	public function new(params:PolymodFileSystemParams)
	{
		super(params);
		archives = new ArchiveMounts(modRoot);
		archives.folderExists = looseFolderExists;
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
		return archives.unmount(dirName);
	}

	public function isMounted(dirName:String):Bool
	{
		return archives.isMounted(dirName);
	}

	public function addFile(path:String, bytes:Bytes):Void
	{
		var key = ArchiveMounts.normalize(path);
		looseFiles.set(key, bytes);
		addFileBytes(key, bytes);
	}

	public function addTextFile(path:String, text:String):Void
	{
		addFile(path, Bytes.ofString(text));
	}

	public function addFolderMod(dirName:String, files:Map<String, Bytes>):Void
	{
		for (path => bytes in files)
			addFile(ArchiveMounts.join(ArchiveMounts.join(archives.root, dirName), ArchiveMounts.normalize(path)), bytes);
	}

	public function removeFolderMod(dirName:String):Void
	{
		var prefix = ArchiveMounts.join(archives.root, dirName) + "/";

		for (key in [for (key in looseFiles.keys()) key])
			if (StringTools.startsWith(key, prefix))
				looseFiles.remove(key);

		rebuildLooseFiles();
	}

	public function clearAll():Void
	{
		archives.unmountAll(true);
		looseFiles = [];
		clear();
	}

	override public function exists(path:String):Bool
	{
		if (archives.hasFile(path) || archives.hasDirectory(path))
			return true;

		return super.exists(ArchiveMounts.normalize(path));
	}

	override public function isDirectory(path:String):Bool
	{
		if (archives.hasDirectory(path))
			return true;

		if (archives.hasFile(path))
			return false;

		return super.isDirectory(ArchiveMounts.normalize(path));
	}

	override public function readDirectory(path:String):Array<String>
	{
		var key = ArchiveMounts.normalize(path);
		var result = super.readDirectory(key);
		var mounted = archives.readDirectory(key);

		if (mounted != null)
			for (child in mounted)
				if (!result.contains(child))
					result.push(child);

		return result;
	}

	override public function readDirectoryRecursive(path:String):Array<String>
	{
		var key = ArchiveMounts.normalize(path);
		var result = super.readDirectoryRecursive(key).filter(file -> file.length > 0);

		for (file in archives.listFiles(key))
			if (!result.contains(file))
				result.push(file);

		return result;
	}

	override public function getFileBytes(path:String):Bytes
	{
		if (archives.hasFile(path))
			return archives.readBytes(path);

		return super.getFileBytes(ArchiveMounts.normalize(path));
	}

	override public function getFileContent(path:String):Null<String>
	{
		var bytes = getFileBytes(path);
		return bytes != null ? bytes.toString() : null;
	}

	override public function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
	{
		for (dir in readDirectory(archives.root))
		{
			var path = Util.pathJoin(modRoot, dir);

			if (!isDirectory(path) || !exists(Util.pathJoin(path, PolymodConfig.modMetadataFile)))
				continue;

			var meta = getMetadataByDir(dir, origin);

			if (meta != null && (meta.id == modId || dir == modId))
				return meta;
		}

		return null;
	}

	function looseFolderExists(path:String):Bool
	{
		return super.isDirectory(ArchiveMounts.normalize(path));
	}

	function rebuildLooseFiles():Void
	{
		clear();

		for (path => bytes in looseFiles)
			addFileBytes(path, bytes);
	}

	function get_root():String
	{
		return archives.root;
	}
}
