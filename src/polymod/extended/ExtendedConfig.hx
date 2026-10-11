package polymod.extended;

import polymod.Polymod.Framework;
import polymod.Polymod.FrameworkParams;
import polymod.backends.IBackend;
import polymod.backends.PolymodAssets.PolymodAssetType;
import polymod.format.ParseRules;
import polymod.extended.structure.FolderMapper.FolderMapping;
import polymod.extended.structure.ModStructure;
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
	?structure:ModStructure,
	?validateStructure:Bool,
	?gameLayout:String,
	?detectLayouts:Bool,
	?layoutMappings:Map<String, Array<FolderMapping>>,
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
