package polymod.extended;

import polymod.Polymod.Framework;
import polymod.Polymod.FrameworkParams;
import polymod.backends.IBackend;
import polymod.backends.PolymodAssets.PolymodAssetType;
import polymod.format.ParseRules;
import thx.semver.VersionRule;

typedef ExtendedConfig =
{
	?modRoot:String,
	?modList:ModList,
	?settings:ModSettings,
	?modListFile:String,
	?settingsFile:String,
	?autoSave:Bool,
	?enableNewMods:Bool,
	?archives:Bool,
	?gameVersion:String,
	?framework:Framework,
	?frameworkParams:FrameworkParams,
	?customBackend:Class<IBackend>,
	?customFilesystem:Dynamic,
	?apiVersionRule:VersionRule,
	?parseRules:ParseRules,
	?ignoredFiles:Array<String>,
	?extensionMap:Map<String, PolymodAssetType>,
	?assetPrefix:String,
	?useScriptedClasses:Bool,
	?loadScriptsAsync:Bool,
	?skipDependencyChecks:Bool,
	?skipDependencyErrors:Bool,
	?maxLogEntries:Int
}
