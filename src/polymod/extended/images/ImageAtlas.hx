package polymod.extended.images;

import haxe.Json;

enum abstract AtlasFormat(String) from String to String
{
	var SPARROW = "sparrow";
	var PACKER = "packer";
	var JSON = "json";
}

typedef AtlasFrame =
{
	name:String,
	x:Int,
	y:Int,
	width:Int,
	height:Int,
	frameX:Int,
	frameY:Int,
	frameWidth:Int,
	frameHeight:Int,
	rotated:Bool
}

class ImageAtlas
{
	public var format(default, null):AtlasFormat;

	public var imagePath(default, null):Null<String>;

	public var frames(default, null):Array<AtlasFrame>;

	public var source(default, null):String;

	public function new(format:AtlasFormat, frames:Array<AtlasFrame>, source:String, ?imagePath:String)
	{
		this.format = format;
		this.frames = frames;
		this.source = source;
		this.imagePath = imagePath;
	}

	public function getFrame(name:String):Null<AtlasFrame>
	{
		for (frame in frames)
			if (frame.name == name)
				return frame;

		return null;
	}

	public function getAnimationNames():Array<String>
	{
		var result:Array<String> = [];

		for (frame in frames)
		{
			var name = animationName(frame.name);

			if (!result.contains(name))
				result.push(name);
		}

		return result;
	}

	public function getAnimationFrames(prefix:String):Array<AtlasFrame>
	{
		var result = frames.filter(frame -> StringTools.startsWith(frame.name, prefix));
		result.sort((a, b) -> a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
		return result;
	}

	public function getBounds():{width:Int, height:Int}
	{
		var width = 0;
		var height = 0;

		for (frame in frames)
		{
			var right = frame.x + (frame.rotated ? frame.height : frame.width);
			var bottom = frame.y + (frame.rotated ? frame.width : frame.height);

			if (right > width)
				width = right;

			if (bottom > height)
				height = bottom;
		}

		return {width: width, height: height};
	}

	public function framesOutside(width:Int, height:Int):Array<AtlasFrame>
	{
		return frames.filter(frame -> frame.x < 0 || frame.y < 0 || frame.x + (frame.rotated ? frame.height : frame.width) > width
			|| frame.y + (frame.rotated ? frame.width : frame.height) > height);
	}

	public static function animationName(frameName:String):String
	{
		var trimmed = ~/\.(png|jpg|jpeg)$/i.replace(frameName, "");
		return ~/[ _-]*\d+$/.replace(trimmed, "");
	}

	public static function parse(text:String, ?hint:AtlasFormat):ImageAtlas
	{
		var format = hint != null ? hint : detect(text);

		return switch (format)
		{
			case SPARROW: parseSparrow(text);
			case JSON: parseJson(text);
			default: parsePacker(text);
		}
	}

	public static function detect(text:String):AtlasFormat
	{
		var trimmed = StringTools.ltrim(text);

		if (StringTools.startsWith(trimmed, "<"))
			return SPARROW;

		if (StringTools.startsWith(trimmed, "{") || StringTools.startsWith(trimmed, "["))
			return JSON;

		return PACKER;
	}

	public static function parseSparrow(text:String):ImageAtlas
	{
		var xml = Xml.parse(text);
		var root = xml.firstElement();

		if (root == null || root.nodeName != "TextureAtlas")
			throw "Sparrow atlas must start with <TextureAtlas>";

		var frames:Array<AtlasFrame> = [];

		for (node in root.elementsNamed("SubTexture"))
		{
			var name = node.get("name");

			if (name == null)
				throw "A <SubTexture> has no name";

			var width = intAttribute(node, "width", 0);
			var height = intAttribute(node, "height", 0);

			frames.push({
				name: name,
				x: intAttribute(node, "x", 0),
				y: intAttribute(node, "y", 0),
				width: width,
				height: height,
				frameX: intAttribute(node, "frameX", 0),
				frameY: intAttribute(node, "frameY", 0),
				frameWidth: intAttribute(node, "frameWidth", width),
				frameHeight: intAttribute(node, "frameHeight", height),
				rotated: node.get("rotated") == "true"
			});
		}

		return new ImageAtlas(SPARROW, frames, text, root.get("imagePath"));
	}

	public static function parsePacker(text:String):ImageAtlas
	{
		var frames:Array<AtlasFrame> = [];
		var line = ~/^\s*(.+?)\s*=\s*(-?\d+)\s+(-?\d+)\s+(\d+)\s+(\d+)\s*$/;

		for (raw in text.split("\n"))
		{
			var clean = StringTools.trim(StringTools.replace(raw, "\r", ""));

			if (clean.length == 0)
				continue;

			if (!line.match(clean))
				throw 'Invalid sprite sheet packer line "$clean"';

			var width = Std.parseInt(line.matched(4));
			var height = Std.parseInt(line.matched(5));

			frames.push({
				name: line.matched(1),
				x: Std.parseInt(line.matched(2)),
				y: Std.parseInt(line.matched(3)),
				width: width,
				height: height,
				frameX: 0,
				frameY: 0,
				frameWidth: width,
				frameHeight: height,
				rotated: false
			});
		}

		return new ImageAtlas(PACKER, frames, text);
	}

	public static function parseJson(text:String):ImageAtlas
	{
		var data:Dynamic = Json.parse(text);
		var animate:Dynamic = Reflect.field(data, "ATLAS");

		if (animate != null)
			return parseAnimateSpritemap(data, text);

		var rawFrames:Dynamic = Reflect.field(data, "frames");
		var frames:Array<AtlasFrame> = [];

		if (rawFrames == null)
			throw "JSON atlas has no \"frames\"";

		if (Std.isOfType(rawFrames, Array))
		{
			for (item in (rawFrames : Array<Dynamic>))
				frames.push(jsonFrame(Reflect.field(item, "filename"), item));
		}
		else
		{
			for (name in Reflect.fields(rawFrames))
				frames.push(jsonFrame(name, Reflect.field(rawFrames, name)));
		}

		var meta:Dynamic = Reflect.field(data, "meta");
		var image:Dynamic = meta != null ? Reflect.field(meta, "image") : null;
		return new ImageAtlas(JSON, frames, text, Std.isOfType(image, String) ? image : null);
	}

	static function parseAnimateSpritemap(data:Dynamic, text:String):ImageAtlas
	{
		var sprites:Dynamic = Reflect.field(Reflect.field(data, "ATLAS"), "SPRITES");
		var frames:Array<AtlasFrame> = [];

		if (!Std.isOfType(sprites, Array))
			throw "Animate spritemap has no \"ATLAS.SPRITES\"";

		for (item in (sprites : Array<Dynamic>))
		{
			var sprite:Dynamic = Reflect.field(item, "SPRITE");

			if (sprite == null || !Std.isOfType(Reflect.field(sprite, "name"), String))
				throw "Animate spritemap has a sprite without a name";

			var width = intField(sprite, "w");
			var height = intField(sprite, "h");
			frames.push({
				name: Reflect.field(sprite, "name"),
				x: intField(sprite, "x"),
				y: intField(sprite, "y"),
				width: width,
				height: height,
				frameX: 0,
				frameY: 0,
				frameWidth: width,
				frameHeight: height,
				rotated: Reflect.field(sprite, "rotated") == true
			});
		}

		var meta:Dynamic = Reflect.field(data, "meta");
		var image:Dynamic = meta != null ? Reflect.field(meta, "image") : null;
		return new ImageAtlas(JSON, frames, text, Std.isOfType(image, String) ? image : null);
	}

	static function jsonFrame(name:Dynamic, item:Dynamic):AtlasFrame
	{
		if (!Std.isOfType(name, String) || item == null)
			throw "JSON atlas frame has no name";

		var frame:Dynamic = Reflect.field(item, "frame");

		if (frame == null)
			throw 'JSON atlas frame "$name" has no "frame"';

		var rotated = Reflect.field(item, "rotated") == true;
		var sprite:Dynamic = Reflect.field(item, "spriteSourceSize");
		var size:Dynamic = Reflect.field(item, "sourceSize");
		var width = intField(frame, "w");
		var height = intField(frame, "h");

		return {
			name: name,
			x: intField(frame, "x"),
			y: intField(frame, "y"),
			width: width,
			height: height,
			frameX: sprite != null ? -intField(sprite, "x") : 0,
			frameY: sprite != null ? -intField(sprite, "y") : 0,
			frameWidth: size != null ? intField(size, "w") : width,
			frameHeight: size != null ? intField(size, "h") : height,
			rotated: rotated
		};
	}

	static function intAttribute(node:Xml, name:String, fallback:Int):Int
	{
		var value = node.get(name);

		if (value == null)
			return fallback;

		var parsed = Std.parseInt(value);

		if (parsed == null)
		{
			var number = Std.parseFloat(value);
			return Math.isNaN(number) ? fallback : Std.int(number);
		}

		return parsed;
	}

	static function intField(data:Dynamic, name:String):Int
	{
		var value:Dynamic = Reflect.field(data, name);
		return Std.isOfType(value, Int) || Std.isOfType(value, Float) ? Std.int(value) : 0;
	}
}
