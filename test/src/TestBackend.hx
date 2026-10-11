package;

import haxe.io.Bytes;
import polymod.Polymod.FrameworkParams;
import polymod.backends.IBackend;
import polymod.backends.PolymodAssetLibrary;
import polymod.backends.PolymodAssets.PolymodAssetType;

class TestBackend implements IBackend
{
	public var polymodLibrary:PolymodAssetLibrary;

	public function new() {}

	public function init(?params:FrameworkParams):Bool
	{
		return true;
	}

	public function destroy():Void {}

	public function clearCache():Void {}

	public function exists(id:String):Bool
	{
		return polymodLibrary != null && polymodLibrary.check(id);
	}

	public function getBytes(id:String):Bytes
	{
		var path = getPath(id);
		return path != null ? polymodLibrary.fileSystem.getFileBytes(path) : null;
	}

	public function getText(id:String):String
	{
		var path = getPath(id);
		return path != null ? polymodLibrary.fileSystem.getFileContent(path) : null;
	}

	#if lime
	public function loadBytes(id:String):lime.app.Future<Bytes>
	{
		return lime.app.Future.withValue(getBytes(id));
	}

	public function loadText(id:String):lime.app.Future<String>
	{
		return lime.app.Future.withValue(getText(id));
	}
	#end

	public function getPath(id:String):String
	{
		return polymodLibrary != null ? polymodLibrary.file(id) : null;
	}

	public function list(type:PolymodAssetType = null):Array<String>
	{
		return polymodLibrary != null ? polymodLibrary.listModFiles(type) : [];
	}

	public function listLibraries():Array<String>
	{
		return [];
	}
}
