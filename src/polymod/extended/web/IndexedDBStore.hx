package polymod.extended.web;

#if js
import js.lib.Promise;

class IndexedDBStore
{
	public var databaseName(default, null):String;

	public var storeName(default, null):String;

	var database:Promise<Dynamic> = null;

	public function new(databaseName:String, storeName:String)
	{
		this.databaseName = databaseName;
		this.storeName = storeName;
	}

	public static function isAvailable():Bool
	{
		return getFactory() != null;
	}

	public function put(key:String, value:Dynamic):Promise<Bool>
	{
		return request("readwrite", store -> store.put(value, key)).then(_ -> true);
	}

	public function get(key:String):Promise<Dynamic>
	{
		return request("readonly", store -> store.get(key));
	}

	public function delete(key:String):Promise<Bool>
	{
		return request("readwrite", store -> store.delete(key)).then(_ -> true);
	}

	public function keys():Promise<Array<String>>
	{
		return request("readonly", store -> store.getAllKeys()).then(result -> [for (key in (result : Array<Dynamic>)) Std.string(key)]);
	}

	public function clear():Promise<Bool>
	{
		return request("readwrite", store -> store.clear()).then(_ -> true);
	}

	public function close():Void
	{
		if (database != null)
			database.then(db -> db.close());

		database = null;
	}

	function request(mode:String, action:Dynamic->Dynamic):Promise<Dynamic>
	{
		return open().then(db -> new Promise<Dynamic>((resolve, reject) ->
		{
			try
			{
				var transaction:Dynamic = db.transaction(storeName, mode);
				var call:Dynamic = action(transaction.objectStore(storeName));
				call.onsuccess = _ -> resolve(call.result);
				call.onerror = _ -> reject(call.error);
			}
			catch (e:Dynamic)
			{
				reject(e);
			}
		}));
	}

	function open():Promise<Dynamic>
	{
		if (database != null)
			return database;

		database = new Promise<Dynamic>((resolve, reject) ->
		{
			var factory:Dynamic = getFactory();

			if (factory == null)
			{
				reject("IndexedDB is not available");
				return;
			}

			try
			{
				var openRequest:Dynamic = factory.open(databaseName, 1);
				openRequest.onupgradeneeded = _ ->
				{
					var db:Dynamic = openRequest.result;

					if (!db.objectStoreNames.contains(storeName))
						db.createObjectStore(storeName);
				};
				openRequest.onsuccess = _ -> resolve(openRequest.result);
				openRequest.onerror = _ -> reject(openRequest.error);
			}
			catch (e:Dynamic)
			{
				reject(e);
			}
		});

		database.catchError(_ -> database = null);
		return database;
	}

	static function getFactory():Dynamic
	{
		return js.Syntax.code("(typeof globalThis.indexedDB !== 'undefined' && globalThis.indexedDB !== null) ? globalThis.indexedDB : null");
	}
}
#end
