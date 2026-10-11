package polymod.extended.desktop;

#if sys
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Entry;
import haxe.zip.Writer;
import polymod.PolymodConfig;
import polymod.extended.archive.Archive;
import polymod.extended.archive.ArchiveFormats;
import polymod.extended.fs.ArchiveFileSystem;
import polymod.extended.fs.ArchiveMounts;
import polymod.extended.util.Signal;

typedef InstallResult =
{
	success:Bool,
	?id:String,
	?path:String,
	?error:String
}

typedef InstallOptions =
{
	?replace:Bool,
	?reload:Bool,
	?enable:Bool
}

typedef CreateModOptions =
{
	?title:String,
	?description:String,
	?author:String,
	?apiVersion:String,
	?modVersion:String,
	?folders:Array<String>,
	?extra:Dynamic
}

class DesktopMods
{
	public static final onInstalled:Signal<String> = new Signal();

	public static final onUninstalled:Signal<String> = new Signal();

	public static final onModsChanged:Signal<Array<String>> = new Signal();

	public static var watcher(default, null):Null<ModWatcher> = null;

	public static var autoReload:Bool = true;

	public static var opener:String->Bool = defaultOpener;

	public static var modRoot(get, never):String;

	public static function openModsFolder():Bool
	{
		if (!sys.FileSystem.exists(modRoot))
			sys.FileSystem.createDirectory(modRoot);

		return opener(sys.FileSystem.absolutePath(modRoot));
	}

	public static function openModFolder(id:String):Bool
	{
		var location = getModLocation(id);

		if (location == null)
			return false;

		return opener(sys.FileSystem.absolutePath(sys.FileSystem.isDirectory(location) ? location : Path.directory(location)));
	}

	public static function getModLocation(id:String):Null<String>
	{
		var mod = PolymodExtended.getMod(id);

		if (mod == null)
			return null;

		var dirName = mod.dirName != null ? mod.dirName : id;
		var fileSystem = PolymodExtended.fileSystem;

		if (Std.isOfType(fileSystem, ArchiveFileSystem))
		{
			var archiveFile = (cast fileSystem : ArchiveFileSystem).getArchiveFile(dirName);

			if (archiveFile != null)
				return archiveFile;
		}

		var folder = Path.join([modRoot, dirName]);
		return sys.FileSystem.exists(folder) ? folder : null;
	}

	public static function isArchiveMod(id:String):Bool
	{
		var location = getModLocation(id);
		return location != null && !sys.FileSystem.isDirectory(location);
	}

	public static function installMod(source:String, ?options:InstallOptions):InstallResult
	{
		if (options == null)
			options = {};

		if (source == null || !sys.FileSystem.exists(source))
			return fail('"$source" does not exist');

		var info = sys.FileSystem.isDirectory(source) ? inspectFolder(source) : inspectArchive(source);

		if (info.error != null)
			return fail(info.error);

		var existing = PolymodExtended.getMod(info.id);

		if (existing != null)
		{
			if (options.replace != true)
				return fail('A mod with the id "${info.id}" is already installed');

			var removed = deleteModFiles(info.id);

			if (removed != null)
				return fail(removed);
		}

		var targetName = sys.FileSystem.isDirectory(source) ? info.id : info.id + "." + Path.extension(source).toLowerCase();
		var target = Path.join([modRoot, targetName]);

		if (sys.FileSystem.exists(target) || sys.FileSystem.exists(Path.join([modRoot, info.id])))
			return fail('"$targetName" already exists in the mods folder');

		try
		{
			if (!sys.FileSystem.exists(modRoot))
				sys.FileSystem.createDirectory(modRoot);

			if (sys.FileSystem.isDirectory(source))
				copyFolder(Path.join([source, info.prefix]), target);
			else
				sys.io.File.copy(source, target);
		}
		catch (e:Dynamic)
		{
			deletePath(target);
			return fail('Could not copy "$source": ${ArchiveMounts.message(e)}');
		}

		if (options.enable != null)
			PolymodExtended.modList.setEnabled(info.id, options.enable);

		finishChange(options.reload != false);
		onInstalled.dispatch(info.id);
		return {success: true, id: info.id, path: target};
	}

	public static function uninstallMod(id:String, reload:Bool = true):Bool
	{
		if (deleteModFiles(id) != null)
			return false;

		PolymodExtended.modList.remove(id);
		PolymodExtended.saveModList();
		finishChange(reload);
		onUninstalled.dispatch(id);
		return true;
	}

	public static function exportMod(id:String, destination:String):InstallResult
	{
		var location = getModLocation(id);

		if (location == null)
			return fail('Mod "$id" is not installed');

		try
		{
			var directory = Path.directory(destination);

			if (directory.length > 0 && !sys.FileSystem.exists(directory))
				sys.FileSystem.createDirectory(directory);

			if (!sys.FileSystem.isDirectory(location))
			{
				sys.io.File.copy(location, destination);
				return {success: true, id: id, path: destination};
			}

			var entries:List<Entry> = new List();

			for (file in listFiles(location))
			{
				var bytes = sys.io.File.getBytes(Path.join([location, file]));
				var entry:Entry = {
					fileName: file,
					fileSize: bytes.length,
					fileTime: Date.now(),
					compressed: false,
					dataSize: bytes.length,
					data: bytes,
					crc32: haxe.crypto.Crc32.make(bytes)
				};
				haxe.zip.Tools.compress(entry, 6);
				entries.add(entry);
			}

			var output = sys.io.File.write(destination, true);
			new Writer(output).write(entries);
			output.close();
			return {success: true, id: id, path: destination};
		}
		catch (e:Dynamic)
		{
			return fail('Could not export "$id": ${ArchiveMounts.message(e)}');
		}
	}

	public static function createMod(id:String, ?options:CreateModOptions):InstallResult
	{
		if (options == null)
			options = {};

		if (id == null || !~/^[A-Za-z0-9_.-]+$/.match(id))
			return fail('"$id" is not a valid mod id, use letters, numbers, "_", "-" and "."');

		var target = Path.join([modRoot, id]);

		if (sys.FileSystem.exists(target) || PolymodExtended.getMod(id) != null)
			return fail('A mod named "$id" already exists');

		var meta:Dynamic = {
			id: id,
			title: options.title != null ? options.title : id,
			description: options.description != null ? options.description : "",
			author: options.author != null ? options.author : "",
			api_version: options.apiVersion != null ? options.apiVersion : "0.1.0",
			mod_version: options.modVersion != null ? options.modVersion : "1.0.0",
			license: ""
		};

		if (options.extra != null)
			for (field in Reflect.fields(options.extra))
				Reflect.setField(meta, field, Reflect.field(options.extra, field));

		try
		{
			sys.FileSystem.createDirectory(target);

			for (folder in (options.folders != null ? options.folders : ["data", "images", "sounds"]))
				sys.FileSystem.createDirectory(Path.join([target, folder]));

			sys.io.File.saveContent(Path.join([target, PolymodConfig.modMetadataFile]), Json.stringify(meta, null, "\t"));
		}
		catch (e:Dynamic)
		{
			deletePath(target);
			return fail('Could not create "$id": ${ArchiveMounts.message(e)}');
		}

		finishChange(true);
		return {success: true, id: id, path: target};
	}

	public static function startWatching(interval:Float = 2.0):ModWatcher
	{
		stopWatching();
		watcher = new ModWatcher(modRoot, interval, [PolymodExtended.config.modListFile, PolymodExtended.config.settingsFile]);
		watcher.onChanged.add(changed ->
		{
			onModsChanged.dispatch(changed);

			if (autoReload && PolymodExtended.initialized)
				PolymodExtended.reload();
		});
		return watcher;
	}

	public static function stopWatching():Void
	{
		if (watcher != null)
			watcher.onChanged.removeAll();

		watcher = null;
	}

	public static function update(elapsed:Float):Bool
	{
		return watcher != null && watcher.update(elapsed);
	}

	#if (lime && !mobile && !html5)
	public static function enableDropInstall(?options:InstallOptions):Void
	{
		var window = lime.app.Application.current != null ? lime.app.Application.current.window : null;

		if (window != null)
			window.onDropFile.add(path -> installMod(path, options));
	}
	#end

	static function finishChange(reload:Bool):Void
	{
		if (watcher != null)
			watcher.reset();

		if (reload && PolymodExtended.initialized)
			PolymodExtended.reload();
	}

	static function deleteModFiles(id:String):Null<String>
	{
		var location = getModLocation(id);

		if (location == null)
			return 'Mod "$id" is not installed';

		var mod = PolymodExtended.getMod(id);
		var fileSystem = PolymodExtended.fileSystem;

		if (mod != null && Std.isOfType(fileSystem, ArchiveFileSystem))
			(cast fileSystem : ArchiveFileSystem).unmount(mod.dirName != null ? mod.dirName : id);

		try
		{
			deletePath(location);
		}
		catch (e:Dynamic)
		{
			return 'Could not delete "$location": ${ArchiveMounts.message(e)}';
		}

		return null;
	}

	static function inspectArchive(path:String):{?id:String, ?prefix:String, ?error:String}
	{
		if (!ArchiveFormats.isArchivePath(path))
			return {error: '"${Path.withoutDirectory(path)}" is not a .zip or .rar file'};

		var archive:Archive;

		try
		{
			archive = ArchiveFormats.openFile(path);
		}
		catch (e:Dynamic)
		{
			return {error: ArchiveMounts.message(e)};
		}

		var unsupported = archive.getUnsupportedEntries();

		if (unsupported.length > 0)
		{
			archive.close();
			return {error: unsupported[0].unsupportedReason};
		}

		var prefix = ArchiveMounts.findContentPrefix(archive);
		var metaPath = prefix + PolymodConfig.modMetadataFile;
		var result = readId(archive.has(metaPath) ? archive.read(metaPath).toString() : null, ArchiveMounts.defaultDirName(path));
		archive.close();
		return result;
	}

	static function inspectFolder(path:String):{?id:String, ?prefix:String, ?error:String}
	{
		var metaFile = PolymodConfig.modMetadataFile;

		if (sys.FileSystem.exists(Path.join([path, metaFile])))
		{
			var result = readId(sys.io.File.getContent(Path.join([path, metaFile])), Path.withoutDirectory(Path.removeTrailingSlashes(path)));
			result.prefix = "";
			return result;
		}

		var children = sys.FileSystem.readDirectory(path).filter(name -> !ArchiveMounts.isIgnored(name));

		if (children.length == 1 && sys.FileSystem.isDirectory(Path.join([path, children[0]]))
			&& sys.FileSystem.exists(Path.join([path, children[0], metaFile])))
		{
			var result = readId(sys.io.File.getContent(Path.join([path, children[0], metaFile])), children[0]);
			result.prefix = children[0];
			return result;
		}

		return {error: 'No $metaFile found in "${Path.withoutDirectory(Path.removeTrailingSlashes(path))}"'};
	}

	static function readId(text:Null<String>, fallback:String):{?id:String, ?prefix:String, ?error:String}
	{
		if (text == null)
			return {error: 'No ${PolymodConfig.modMetadataFile} found'};

		try
		{
			var data:Dynamic = Json.parse(text);
			var id:Dynamic = Reflect.field(data, "id");
			var value:String = Std.isOfType(id, String) && (id : String).length > 0 ? id : fallback;

			if (!~/^[A-Za-z0-9_.-]+$/.match(value))
				return {error: 'Mod id "$value" can only use letters, numbers, "_", "-" and "."'};

			return {id: value, prefix: ""};
		}
		catch (e:Dynamic)
		{
			return {error: 'Invalid ${PolymodConfig.modMetadataFile}: ${Std.string(e)}'};
		}
	}

	static function copyFolder(source:String, target:String):Void
	{
		sys.FileSystem.createDirectory(target);

		for (name in sys.FileSystem.readDirectory(source))
		{
			if (ArchiveMounts.isIgnored(name))
				continue;

			var from = Path.join([source, name]);
			var to = Path.join([target, name]);

			if (sys.FileSystem.isDirectory(from))
				copyFolder(from, to);
			else
				sys.io.File.copy(from, to);
		}
	}

	static function listFiles(folder:String, relative:String = ""):Array<String>
	{
		var result:Array<String> = [];
		var current = relative.length > 0 ? Path.join([folder, relative]) : folder;

		for (name in sys.FileSystem.readDirectory(current))
		{
			var child = relative.length > 0 ? relative + "/" + name : name;

			if (sys.FileSystem.isDirectory(Path.join([folder, child])))
				result = result.concat(listFiles(folder, child));
			else if (!ArchiveMounts.isIgnored(child))
				result.push(child);
		}

		return result;
	}

	static function deletePath(path:String):Void
	{
		if (!sys.FileSystem.exists(path))
			return;

		if (!sys.FileSystem.isDirectory(path))
		{
			sys.FileSystem.deleteFile(path);
			return;
		}

		for (name in sys.FileSystem.readDirectory(path))
			deletePath(Path.join([path, name]));

		sys.FileSystem.deleteDirectory(path);
	}

	static function defaultOpener(path:String):Bool
	{
		var command = switch (Sys.systemName())
		{
			case "Windows": "explorer";
			case "Mac": "open";
			case "Linux", "BSD": "xdg-open";
			default: null;
		}

		if (command == null)
			return false;

		try
		{
			var process = new sys.io.Process(command, [Sys.systemName() == "Windows" ? StringTools.replace(path, "/", "\\") : path], true);
			process.close();
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	static function fail(message:String):InstallResult
	{
		return {success: false, error: message};
	}

	static function get_modRoot():String
	{
		var root = PolymodExtended.config.modRoot;
		return root != null ? root : PolymodExtended.DEFAULT_MOD_ROOT;
	}
}
#end
