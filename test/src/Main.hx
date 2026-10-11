package;

import polymod.Polymod.Framework;
import polymod.extended.ModList;
import polymod.extended.PolymodExtended;
import polymod.extended.util.Signal;

class Main
{
	static var passed:Int = 0;
	static var failed:Int = 0;

	static function main():Void
	{
		testSignal();
		testModList();
		testPolymodExtended();

		Sys.println('Passed: $passed, Failed: $failed');
		Sys.exit(failed > 0 ? 1 : 0);
	}

	static function testSignal():Void
	{
		var signal = new Signal<Int>();
		var total = 0;
		var listener = (value:Int) -> total += value;

		signal.add(listener);
		signal.add(listener);
		signal.addOnce(value -> total += value * 10);
		signal.dispatch(1);
		signal.dispatch(1);
		check("Signal dispatches regular and once listeners", total == 12);

		signal.remove(listener);
		signal.dispatch(5);
		check("Signal removes listeners", total == 12 && signal.count == 0);
	}

	static function testModList():Void
	{
		var list = new ModList();
		list.add("a");
		list.add("b", false);
		list.add("c");
		list.add("a");
		check("ModList ignores duplicates", list.length == 3);
		check("ModList returns enabled ids in order", list.getEnabledIds().join(",") == "a,c");

		list.move("c", 0);
		check("ModList moves entries", list.getEnabledIds().join(",") == "c,a");

		list.toggle("b");
		check("ModList toggles entries", list.isEnabled("b"));

		var restored = ModList.fromJson(list.toJson());
		check("ModList survives JSON round trip", restored.toJson() == list.toJson());
		check("ModList handles invalid JSON", ModList.fromJson("{oops").length == 0);

		list.sync(["a", "d"], false);
		check("ModList sync removes missing and adds new", list.length == 2 && list.has("d") && !list.isEnabled("d"));
	}

	static function testPolymodExtended():Void
	{
		var loaded = PolymodExtended.init({
			modRoot: "mods",
			framework: Framework.CUSTOM,
			customBackend: TestBackend
		});

		check("Scan finds both sample mods", PolymodExtended.availableMods.length == 2);
		check("Init loads every new mod", loaded.length == 2);
		check("Dependencies load first", PolymodExtended.getLoadedModIds().join(",") == "base_mod,addon_mod");
		check("Metadata lookup works", PolymodExtended.getMod("addon_mod") != null);

		var loadedSignal = false;
		PolymodExtended.onModsLoaded.addOnce(_ -> loadedSignal = true);
		PolymodExtended.setModEnabled("addon_mod", false, true);
		check("Disabled mod is unloaded on reload", !PolymodExtended.isModLoaded("addon_mod") && PolymodExtended.isModLoaded("base_mod"));
		check("Reload dispatches onModsLoaded", loadedSignal);

		PolymodExtended.setModEnabled("addon_mod", true, true);
		check("Enabled mod is loaded on reload", PolymodExtended.isModLoaded("addon_mod"));

		PolymodExtended.unloadAll();
		check("Unload clears loaded mods", PolymodExtended.loadedMods.length == 0);
		check("No errors were logged", !PolymodExtended.log.hasErrors());

		if (PolymodExtended.log.hasErrors())
			Sys.println(PolymodExtended.log.format());
	}

	static function check(name:String, condition:Bool):Void
	{
		if (condition)
			passed++;
		else
			failed++;

		Sys.println((condition ? "[PASS] " : "[FAIL] ") + name);
	}
}
