import fs from 'node:fs';
import path from 'node:path';
const root = process.cwd();
const previousProject = fs.existsSync('MNetBox.xcodeproj/project.pbxproj') ? fs.readFileSync('MNetBox.xcodeproj/project.pbxproj', 'utf8') : '';
const teams = [...new Set([...previousProject.matchAll(/DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]{10})"?;/g)].map(m => m[1]))];
if (teams.length > 1) throw new Error('Multiple signing teams: preserve configuration manually before generating.');
const appSigning = teams.length === 1 ? 'DEVELOPMENT_TEAM = '+teams[0]+'; ' : '';
function existingSetting(key, fallback, pattern) {
 const values = [...new Set([...previousProject.matchAll(new RegExp(key+'\\s*=\\s*"?([^";\\s]+)"?;', 'g'))].map(m=>m[1]))];
 if (values.length > 1 || (values.length === 1 && !pattern.test(values[0]))) throw new Error('Invalid or conflicting '+key);
 return values[0] ?? fallback;
}
// Override with BUNDLE_PREFIX for a personal signing identity.
const bundlePrefix = process.env.BUNDLE_PREFIX || 'io.github.overnite22';
if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(bundlePrefix)) throw new Error('Invalid BUNDLE_PREFIX');
const appVersion = existingSetting('MARKETING_VERSION', '0.16.0', /^\d+\.\d+\.\d+$/);
const appBuild = existingSetting('CURRENT_PROJECT_VERSION', '34', /^\d+$/);
const objects = [];
let sequence = 1;
const id = () => (sequence++).toString(16).toUpperCase().padStart(24, '0');
const add = (body) => { const key=id(); objects.push([key,body]); return key; };
const quote = JSON.stringify;
const list = (items) => '(' + items.join(', ') + (items.length ? ',' : '') + ')';
const walk = (dir) => fs.readdirSync(dir,{withFileTypes:true}).flatMap(e => e.isDirectory() ? walk(path.join(dir,e.name)) : [path.join(dir,e.name)]).filter(f=>f.endsWith('.swift'));
const groupID=id(), projectID=id(), productsID=id();
const productIDs=[];
const targetIDs=[];
const appTargetID=id();
function target(name,dir,productType,test=false,ui=false) {
 const targetID = test ? id() : appTargetID;
 targetIDs.push(targetID);
 const files=walk(dir).map(f=>{
  const ref=add('isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quote(f.replaceAll('\\','/'))+'; sourceTree = SOURCE_ROOT;');
  const build=add('isa = PBXBuildFile; fileRef = '+ref+';');
  return {ref,build};
 });
 const resourceFiles = test ? [] : [['MNetBox/Resources/Localizable.xcstrings','text.json.xcstrings'],['MNetBox/Resources/Assets.xcassets','folder.assetcatalog'],['MNetBox/Resources/PrivacyInfo.xcprivacy','text.xml']].map(([file,type]) => {
  const ref = add('isa = PBXFileReference; lastKnownFileType = '+type+'; path = '+quote(file)+'; sourceTree = SOURCE_ROOT;');
  const build = add('isa = PBXBuildFile; fileRef = '+ref+';'); return {ref,build};
 });
 const group=add('isa = PBXGroup; children = '+list([...files,...resourceFiles].map(f=>f.ref))+'; name = '+name+'; sourceTree = "<group>";');
 groups.push(group);
 const product=add('isa = PBXFileReference; explicitFileType = '+(test?'wrapper.cfbundle':'wrapper.application')+'; includeInIndex = 0; path = '+name+(test?'.xctest':'.app')+'; sourceTree = BUILT_PRODUCTS_DIR;');
 productIDs.push(product);
 const sources=add('isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+list(files.map(f=>f.build))+'; runOnlyForDeploymentPostprocessing = 0;');
 const frameworks=add('isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;');
 const resources=add('isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+list(resourceFiles.map(f=>f.build))+'; runOnlyForDeploymentPostprocessing = 0;');
 const configs=['Debug','Release'].map(nameConfig=>add('isa = XCBuildConfiguration; name = '+nameConfig+'; buildSettings = { PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = '+bundlePrefix+'.'+name+'; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = complete; IPHONEOS_DEPLOYMENT_TARGET = 26.0; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO; '+(!test?appSigning+'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait; INFOPLIST_KEY_CFBundleDisplayName = MNetBox; CURRENT_PROJECT_VERSION = '+appBuild+'; MARKETING_VERSION = '+appVersion+'; ':ui?'TEST_TARGET_NAME = MNetBox; ':'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/MNetBox.app/MNetBox"; BUNDLE_LOADER = "$(TEST_HOST)"; ')+'};'));
 const configList=add('isa = XCConfigurationList; buildConfigurations = '+list(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;');
 const deps=[];
 if(test) {
  const proxy=add('isa = PBXContainerItemProxy; containerPortal = '+projectID+'; proxyType = 1; remoteGlobalIDString = '+appTargetID+'; remoteInfo = MNetBox;');
  deps.push(add('isa = PBXTargetDependency; target = '+appTargetID+'; targetProxy = '+proxy+';'));
 }
 objects.push([targetID,'isa = PBXNativeTarget; buildConfigurationList = '+configList+'; buildPhases = '+list([sources,frameworks,resources])+'; buildRules = (); dependencies = '+list(deps)+'; name = '+name+'; productName = '+name+'; productReference = '+product+'; productType = '+quote(productType)+';']);
 return targetID;
}
const groups=[];
target('MNetBox','MNetBox','com.apple.product-type.application');
const unit=target('MNetBoxTests','MNetBoxTests','com.apple.product-type.bundle.unit-test',true);
const ui=target('MNetBoxUITests','MNetBoxUITests','com.apple.product-type.bundle.ui-testing',true,true);
objects.push([productsID,'isa = PBXGroup; children = '+list(productIDs)+'; name = Products; sourceTree = "<group>";']);
objects.push([groupID,'isa = PBXGroup; children = '+list([...groups,productsID])+'; sourceTree = "<group>";']);
const configs=['Debug','Release'].map(name=>add('isa = XCBuildConfiguration; name = '+name+'; buildSettings = { SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SWIFT_OPTIMIZATION_LEVEL = '+quote(name==='Debug'?'-Onone':'-O')+'; '+(name==='Debug'?'ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;':'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')+' };'));
const configList=add('isa = XCConfigurationList; buildConfigurations = '+list(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;');
objects.push([projectID,'isa = PBXProject; attributes = { LastUpgradeCheck = 2700; }; buildConfigurationList = '+configList+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, fr, Base); mainGroup = '+groupID+'; productRefGroup = '+productsID+'; projectDirPath = ""; projectRoot = ""; targets = '+list(targetIDs)+';']);
fs.mkdirSync('MNetBox.xcodeproj/xcshareddata/xcschemes',{recursive:true});
fs.writeFileSync('MNetBox.xcodeproj/project.pbxproj','// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+objects.map(([k,v])=>k+' = { '+v+' };').join('\n')+'\n}; rootObject = '+projectID+'; }\n');
const ref=(key,name)=>'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+key+'" BuildableName="'+name+(name==='MNetBox'?'.app':'.xctest')+'" BlueprintName="'+name+'" ReferencedContainer="container:MNetBox.xcodeproj"/>';
fs.writeFileSync('MNetBox.xcodeproj/xcshareddata/xcschemes/MNetBox.xcscheme','<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+ref(appTargetID,'MNetBox')+'</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">'+ref(unit,'MNetBoxTests')+'</TestableReference><TestableReference skipped="NO">'+ref(ui,'MNetBoxUITests')+'</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref(appTargetID,'MNetBox')+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref(appTargetID,'MNetBox')+'</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>');
console.log('Generated project with '+targetIDs.length+' targets.');
