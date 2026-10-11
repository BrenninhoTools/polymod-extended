package polymod.extended.images;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod.ModMetadata;
import polymod.extended.images.ImageAtlas.AtlasFormat;
import polymod.util.Util;

typedef ModImage =
{
	id:String,
	path:String,
	modId:String,
	extension:String
}

typedef ImageIssue =
{
	id:String,
	message:String
}

typedef ImageOverride =
{
	id:String,
	mods:Array<String>
}

class ModImages
{
	public static var folder:String = "images";

	public static var extensions:Array<String> = ["png", "jpg", "jpeg"];

	public static var atlasExtensions:Array<String> = ["xml", "txt", "json"];

	public static var maxTextureSize:Int = 8192;

	public static var cacheBytes:Bool = true;

	static var listening:Bool = false;
	static var bytesCache:Map<String, Bytes> = [];
	static var atlasCache:Map<String, ImageAtlas> = [];
	static var resolveCache:Map<String, Null<ModImage>> = [];

	#if (openfl && !macro)
	static var bitmapCache:Map<String, openfl.display.BitmapData> = [];
	#end

	public static function resolve(id:String):Null<ModImage>
	{
		listen();
		var key = normalizeId(id);

		if (key == null)
			return null;

		if (resolveCache.exists(key))
			return resolveCache.get(key);

		var result = find(key);
		resolveCache.set(key, result);
		return result;
	}

	public static function exists(id:String):Bool
	{
		return resolve(id) != null;
	}

	public static function getSource(id:String):Null<String>
	{
		var image = resolve(id);
		return image != null ? image.modId : null;
	}

	public static function getBytes(id:String):Null<Bytes>
	{
		var image = resolve(id);

		if (image == null)
			return null;

		if (cacheBytes && bytesCache.exists(image.path))
			return bytesCache.get(image.path);

		var bytes = PolymodExtended.fileSystem.getFileBytes(image.path);

		if (bytes != null && cacheBytes)
			bytesCache.set(image.path, bytes);

		return bytes;
	}

	public static function getInfo(id:String):Null<ImageInfo>
	{
		return ImageInfo.read(getBytes(id));
	}

	public static function getAtlasText(id:String):Null<{text:String, format:AtlasFormat, path:String, modId:String}>
	{
		var image = resolve(id);
		var key = normalizeId(id);

		if (key == null)
			return null;

		var mods = PolymodExtended.loadedMods;
		var order = image != null ? [for (mod in mods) if (mod.id == image.modId) mod].concat(mods.filter(mod -> mod.id != image.modId)) : mods.copy();

		if (image == null)
			order.reverse();

		var base = image != null ? image.id : resolveAlias(key);

		for (mod in order)
			for (extension in atlasExtensions)
			{
				var path = Util.pathJoin(modPath(mod), Util.pathJoin(folder, base + "." + extension));

				if (PolymodExtended.fileSystem.exists(path))
				{
					var text = PolymodExtended.fileSystem.getFileContent(path);

					if (text != null)
						return {text: text, format: formatFor(extension, text), path: path, modId: mod.id};
				}
			}

		return null;
	}

	public static function getAtlas(id:String):Null<ImageAtlas>
	{
		var data = getAtlasText(id);

		if (data == null)
			return null;

		if (atlasCache.exists(data.path))
			return atlasCache.get(data.path);

		try
		{
			var atlas = ImageAtlas.parse(data.text, data.format);
			atlasCache.set(data.path, atlas);
			return atlas;
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	public static function list(?subfolder:String):Array<String>
	{
		var result:Array<String> = [];

		for (mod in PolymodExtended.loadedMods)
			for (id in listMod(mod, subfolder))
				if (!result.contains(id))
					result.push(id);

		result.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	public static function listMod(mod:ModMetadata, ?subfolder:String):Array<String>
	{
		var root = Util.pathJoin(modPath(mod), folder);
		var fs = PolymodExtended.fileSystem;

		if (!fs.exists(root) || !fs.isDirectory(root))
			return [];

		var prefix = subfolder != null ? polymod.extended.archive.Archive.normalizePath(subfolder) : "";
		var result:Array<String> = [];

		for (file in fs.readDirectoryRecursive(root))
		{
			var clean = StringTools.replace(file, "\\", "/");

			if (!extensions.contains(Path.extension(clean).toLowerCase()))
				continue;

			var id = Path.withoutExtension(clean);

			if (prefix.length == 0 || StringTools.startsWith(id, prefix + "/"))
				result.push(id);
		}

		return result;
	}

	public static function getOverrides():Array<ImageOverride>
	{
		var owners:Map<String, Array<String>> = [];

		for (mod in PolymodExtended.loadedMods)
			for (id in listMod(mod))
			{
				var list = owners.get(id);

				if (list == null)
				{
					list = [];
					owners.set(id, list);
				}

				list.push(mod.id);
			}

		var result = [for (id => mods in owners) if (mods.length > 1) {id: id, mods: mods}];
		result.sort((a, b) -> a.id < b.id ? -1 : (a.id > b.id ? 1 : 0));
		return result;
	}

	public static function validateMod(modId:String):Array<ImageIssue>
	{
		var mod = PolymodExtended.getMod(modId);
		var issues:Array<ImageIssue> = [];

		if (mod == null)
			return issues;

		var fs = PolymodExtended.fileSystem;
		var root = Util.pathJoin(modPath(mod), folder);

		for (id in listMod(mod))
		{
			var path = imagePath(mod, id);

			if (path == null)
				continue;

			var info = ImageInfo.read(fs.getFileBytes(path));

			if (info == null)
			{
				issues.push({id: id, message: '"$id" is not a valid image file'});
				continue;
			}

			if (info.width > maxTextureSize || info.height > maxTextureSize)
				issues.push({id: id, message: '"$id" is ${info.width}x${info.height}, larger than the ${maxTextureSize}px limit'});

			for (extension in atlasExtensions)
			{
				var atlasPath = Util.pathJoin(root, id + "." + extension);

				if (!fs.exists(atlasPath))
					continue;

				var text = fs.getFileContent(atlasPath);
				var format = formatFor(extension, text);

				if (format == PACKER && extension != "txt")
					continue;

				try
				{
					var atlas = ImageAtlas.parse(text, format);
					var outside = atlas.framesOutside(info.width, info.height);

					if (outside.length > 0)
						issues.push({id: id, message: '${outside.length} frame(s) of "$id.$extension" are outside the image, like "${outside[0].name}"'});
				}
				catch (e:Dynamic)
				{
					issues.push({id: id, message: '"$id.$extension" is not a valid atlas: ${Std.string(e)}'});
				}
			}
		}

		var images = listMod(mod);

		var allFiles = fs.exists(root) && fs.isDirectory(root) ? fs.readDirectoryRecursive(root) : [];

		for (file in allFiles)
		{
			var clean = StringTools.replace(file, "\\", "/");
			var extension = Path.extension(clean).toLowerCase();

			if (extension == "xml" && !images.contains(Path.withoutExtension(clean)))
				issues.push({id: Path.withoutExtension(clean), message: '"$clean" has no image with the same name'});
		}

		return issues;
	}

	public static function clearCache():Void
	{
		bytesCache = [];
		atlasCache = [];
		resolveCache = [];

		#if (openfl && !macro)
		for (bitmap in bitmapCache)
			bitmap.dispose();

		bitmapCache = [];
		#end
	}

	#if (lime && !macro)
	public static function getImage(id:String):Null<lime.graphics.Image>
	{
		var bytes = getBytes(id);
		return bytes != null ? lime.graphics.Image.fromBytes(bytes) : null;
	}
	#end

	#if (openfl && !macro)
	public static function getBitmapData(id:String, cache:Bool = true):Null<openfl.display.BitmapData>
	{
		var image = resolve(id);

		if (image == null)
			return null;

		if (cache && bitmapCache.exists(image.path))
			return bitmapCache.get(image.path);

		var bytes = getBytes(id);
		var bitmap = bytes != null ? openfl.display.BitmapData.fromBytes(bytes) : null;

		if (bitmap != null && cache)
			bitmapCache.set(image.path, bitmap);

		return bitmap;
	}
	#end

	#if (flixel && !macro)
	public static function getFrames(id:String):Null<flixel.graphics.frames.FlxAtlasFrames>
	{
		var bitmap = getBitmapData(id);
		var atlas = getAtlasText(id);

		if (bitmap == null || atlas == null)
			return null;

		var graphic = flixel.graphics.FlxGraphic.fromBitmapData(bitmap, false, "polymod-extended:" + resolve(id).path);

		return switch (atlas.format)
		{
			case SPARROW: flixel.graphics.frames.FlxAtlasFrames.fromSparrow(graphic, atlas.text);
			case JSON: flixel.graphics.frames.FlxAtlasFrames.fromTexturePackerJson(graphic, atlas.text);
			default: flixel.graphics.frames.FlxAtlasFrames.fromSpriteSheetPacker(graphic, atlas.text);
		}
	}
	#end

	public static function resolveAlias(id:String):String
	{
		var current = id;
		var seen:Array<String> = [];
		var mods = PolymodExtended.loadedMods;

		while (!seen.contains(current))
		{
			seen.push(current);
			var next:Null<String> = null;

			var index = mods.length - 1;

			while (index >= 0)
			{
				var alias = PolymodExtended.getModOptions(mods[index].id).imageAliases.get(current);

				if (alias != null)
				{
					next = normalizeId(alias);
					break;
				}

				index--;
			}

			if (next == null)
				return current;

			current = next;
		}

		return current;
	}

	static function find(id:String):Null<ModImage>
	{
		var target = resolveAlias(id);
		var mods = PolymodExtended.loadedMods;
		var index = mods.length - 1;

		while (index >= 0)
		{
			var mod = mods[index];
			var path = imagePath(mod, target);

			if (path != null)
				return {id: target, path: path, modId: mod.id, extension: Path.extension(path).toLowerCase()};

			index--;
		}

		return null;
	}

	static function imagePath(mod:ModMetadata, id:String):Null<String>
	{
		var base = Util.pathJoin(modPath(mod), Util.pathJoin(folder, id));
		var given = Path.extension(id).toLowerCase();

		if (extensions.contains(given) && PolymodExtended.fileSystem.exists(base))
			return base;

		for (extension in extensions)
		{
			var path = base + "." + extension;

			if (PolymodExtended.fileSystem.exists(path))
				return path;
		}

		return null;
	}

	static function formatFor(extension:String, text:String):AtlasFormat
	{
		return switch (extension.toLowerCase())
		{
			case "xml": SPARROW;
			case "json": JSON;
			default: ImageAtlas.detect(text != null ? text : "");
		}
	}

	static function normalizeId(id:String):Null<String>
	{
		var clean = polymod.extended.archive.Archive.normalizePath(id);

		if (clean == null || clean.length == 0)
			return null;

		if (StringTools.startsWith(clean, folder + "/"))
			clean = clean.substr(folder.length + 1);

		var extension = Path.extension(clean).toLowerCase();
		return extensions.contains(extension) ? Path.withoutExtension(clean) : clean;
	}

	static function modPath(mod:ModMetadata):String
	{
		return mod.modPath != null ? mod.modPath : Util.pathJoin(PolymodExtended.config.modRoot, mod.dirName);
	}

	static function listen():Void
	{
		if (listening)
			return;

		listening = true;
		PolymodExtended.onModsLoaded.add(_ -> clearCache());
	}
}
