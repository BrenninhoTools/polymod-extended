package polymod.extended.sources;

import haxe.Json;
import polymod.extended.sources.ModSources.ResolvedMod;

typedef SourceRecord =
{
	link:String,
	source:String,
	?sourceId:String,
	?fileId:String,
	?fileName:String,
	?version:String,
	?updatedAt:Float,
	?etag:String,
	?lastModified:String,
	installedAt:Float
}

typedef UpdateInfo =
{
	id:String,
	record:SourceRecord,
	?latest:ResolvedMod,
	hasUpdate:Bool,
	?error:String
}

class SourceRecords
{
	public var records(default, null):Map<String, SourceRecord> = [];

	public function new() {}

	public function get(id:String):Null<SourceRecord>
	{
		return records.get(id);
	}

	public function set(id:String, link:String, mod:ResolvedMod, ?etag:String, ?lastModified:String):SourceRecord
	{
		var record:SourceRecord = {
			link: link,
			source: mod.source,
			sourceId: mod.sourceId,
			fileId: mod.fileId,
			fileName: mod.fileName,
			version: mod.version,
			updatedAt: mod.updatedAt,
			etag: etag,
			lastModified: lastModified,
			installedAt: Date.now().getTime()
		};
		records.set(id, record);
		return record;
	}

	public function remove(id:String):Bool
	{
		return records.remove(id);
	}

	public function ids():Array<String>
	{
		var result = [for (id in records.keys()) id];
		result.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	public static function isNewer(record:SourceRecord, latest:ResolvedMod):Bool
	{
		if (latest == null)
			return false;

		if (record.fileId != null && latest.fileId != null && record.fileId != latest.fileId)
			return true;

		if (record.updatedAt != null && latest.updatedAt != null && latest.updatedAt > record.updatedAt)
			return true;

		if (record.version != null && latest.version != null && record.version != latest.version)
			return true;

		return false;
	}

	public function toJson():String
	{
		var data:Dynamic = {};

		for (id => record in records)
			Reflect.setField(data, id, record);

		return Json.stringify(data, null, "\t");
	}

	public static function fromJson(text:String):SourceRecords
	{
		var result = new SourceRecords();

		if (text == null || StringTools.trim(text).length == 0)
			return result;

		try
		{
			var data:Dynamic = Json.parse(text);

			for (id in Reflect.fields(data))
			{
				var record:Dynamic = Reflect.field(data, id);

				if (record != null && Std.isOfType(Reflect.field(record, "link"), String))
					result.records.set(id, record);
			}
		}
		catch (e:Dynamic) {}

		return result;
	}
}
