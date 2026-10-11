package polymod.extended.structure;

import polymod.extended.structure.ModStructure.FolderRule;

class StructurePresets
{
	static final DATA:Array<String> = ["json", "xml", "txt", "csv", "tsv", "yaml", "yml"];
	static final IMAGES:Array<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "astc", "ktx", "ktx2", "xml", "json", "txt"];
	static final AUDIO:Array<String> = ["ogg", "wav", "mp3", "flac"];
	static final FONTS:Array<String> = ["ttf", "otf", "woff", "woff2"];
	static final VIDEOS:Array<String> = ["mp4", "webm", "mov"];
	static final SHADERS:Array<String> = ["frag", "vert", "glsl"];

	public static function get(name:String):Null<ModStructure>
	{
		return switch (name != null ? name.toLowerCase() : "")
		{
			case "generic", "default": generic();
			case "psych", "psych-engine", "psychengine": psych();
			case "vslice", "v-slice", "base", "basegame", "funkin": vslice();
			case "codename", "codename-engine", "codenameengine": codename();
			default: null;
		}
	}

	public static function generic():ModStructure
	{
		return new ModStructure("generic", [
			folder("data", DATA, true),
			folder("images", IMAGES, true),
			folder("sounds", AUDIO, true),
			folder("music", AUDIO),
			folder("songs", AUDIO.concat(["json"])),
			folder("fonts", FONTS),
			folder("videos", VIDEOS),
			folder("scripts", ["hx", "hxs", "hxc", "hscript", "lua"]),
			folder("shaders", SHADERS)
		]);
	}

	public static function psych():ModStructure
	{
		var structure = new ModStructure("psych", [
			folder("images", IMAGES, true),
			folder("characters", ["json"], true),
			folder("data", DATA.concat(["lua", "hx"]), true),
			folder("songs", AUDIO.concat(["json", "lua", "hx"]), true),
			folder("music", AUDIO),
			folder("sounds", AUDIO),
			folder("stages", ["json", "lua", "hx"]),
			folder("weeks", ["json"]),
			folder("scripts", ["lua", "hx"]),
			folder("custom_events", ["lua", "hx", "txt"]),
			folder("custom_notetypes", ["lua", "hx", "txt"]),
			folder("achievements", ["json"]),
			folder("fonts", FONTS),
			folder("shaders", SHADERS),
			folder("videos", VIDEOS)
		]);
		structure.extensionTargets.set("lua", "scripts");
		structure.extensionTargets.set("hx", "scripts");
		return structure;
	}

	public static function vslice():ModStructure
	{
		var structure = new ModStructure("vslice", [
			folder("data", DATA, true),
			folder("images", IMAGES, true),
			folder("songs", AUDIO, true),
			folder("music", AUDIO.concat(["json"])),
			folder("sounds", AUDIO),
			folder("scripts", ["hxc", "hx"]),
			folder("shaders", SHADERS),
			folder("videos", VIDEOS),
			folder("fonts", FONTS)
		]);
		structure.extensionTargets.set("hxc", "scripts");
		structure.extensionTargets.set("hx", "scripts");
		return structure;
	}

	public static function codename():ModStructure
	{
		var structure = new ModStructure("codename", [
			folder("data", DATA.concat(["hx", "hscript", "lua"]), true),
			folder("images", IMAGES, true),
			folder("songs", AUDIO.concat(["json", "hx", "hscript", "lua"]), true),
			folder("music", AUDIO.concat(["ini"])),
			folder("sounds", AUDIO),
			folder("shaders", SHADERS),
			folder("videos", VIDEOS),
			folder("fonts", FONTS)
		]);
		structure.extensionTargets.set("hx", "data");
		structure.extensionTargets.set("hscript", "data");
		return structure;
	}

	static function folder(path:String, extensions:Array<String>, template:Bool = false):FolderRule
	{
		return {path: path, extensions: extensions, template: template};
	}
}
