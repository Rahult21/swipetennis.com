#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project with stable identifiers."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent
objects={}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key, value): objects[uid(key)]=value; return uid(key)
def items(values): return '('+','.join(values)+')'
def configs(key, settings):
    ids=[]
    for name in ['Debug','Release']:
        values=dict(settings)
        values['ONLY_ACTIVE_ARCH']='YES' if name=='Debug' else 'NO'
        values['SWIFT_OPTIMIZATION_LEVEL']='"-Onone"' if name=='Debug' else '"-O"'
        ids.append(add(key+name,'{isa = XCBuildConfiguration; name = '+name+'; buildSettings = {'+' '.join(k+' = '+v+';' for k,v in values.items())+'};}'))
    return add(key+'configs','{isa = XCConfigurationList; buildConfigurations = '+items(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
app=uid('app'); test=uid('uitest')
files=[]; source=[]; resources=[]
for path in sorted((root/'SwipeTennis').rglob('*')):
    if not path.is_file() or 'Assets.xcassets/' in str(path): continue
    rel=str(path.relative_to(root)); ext=path.suffix
    if ext not in ['.swift','.wav','.xcprivacy','.pdf','.mp4']: continue
    typ={'.swift':'sourcecode.swift','.wav':'audio.wav','.xcprivacy':'text.xml','.pdf':'image.pdf','.mp4':'file'}[ext]
    ref=add(rel,'{isa = PBXFileReference; lastKnownFileType = '+typ+'; path = "'+rel+'"; sourceTree = SOURCE_ROOT;}'); files.append(ref)
    build=add(rel+'build','{isa = PBXBuildFile; fileRef = '+ref+';}')
    (source if ext=='.swift' else resources).append(build)
asset=add('assets','{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = SwipeTennis/Assets.xcassets; sourceTree = SOURCE_ROOT;}'); files.append(asset)
resources.append(add('assetsbuild','{isa = PBXBuildFile; fileRef = '+asset+';}'))
product=add('product','{isa = PBXFileReference; explicitFileType = wrapper.application; path = SwipeTennis.app; sourceTree = BUILT_PRODUCTS_DIR;}')
testproduct=add('testproduct','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SwipeTennisUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
ui=add('uitestfile','{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SwipeTennisUITests/SwipeTennisUITests.swift; sourceTree = SOURCE_ROOT;}'); files.append(ui)
uibuild=add('uitestbuild','{isa = PBXBuildFile; fileRef = '+ui+';}')
products=add('products','{isa = PBXGroup; name = Products; children = '+items([product,testproduct])+'; sourceTree = "<group>";}')
group=add('main','{isa = PBXGroup; children = '+items(files+[products])+'; sourceTree = "<group>";}')
def phase(key, typ, files): return add(key,'{isa = '+typ+'; buildActionMask = 2147483647; files = '+items(files)+'; runOnlyForDeploymentPostprocessing = 0;}')
phases=[phase('sources','PBXSourcesBuildPhase',source),phase('frameworks','PBXFrameworksBuildPhase',[]),phase('resources','PBXResourcesBuildPhase',resources)]
common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','TARGETED_DEVICE_FAMILY':'"1,2"','CODE_SIGN_STYLE':'Automatic','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_EMIT_LOC_STRINGS':'YES'}
settings=dict(common,PRODUCT_BUNDLE_IDENTIFIER='com.swipetennis.app',PRODUCT_NAME='"$(TARGET_NAME)"',INFOPLIST_FILE='SwipeTennis/Info.plist',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',SUPPORTED_PLATFORMS='"iphoneos iphonesimulator"',SUPPORTS_MACCATALYST='NO',SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD='NO')
settings['CODE_SIGN_ENTITLEMENTS']='SwipeTennis/SwipeTennis.entitlements'
appconfig=configs('app',settings)
add('app','{isa = PBXNativeTarget; name = SwipeTennis; productName = SwipeTennis; productType = "com.apple.product-type.application"; productReference = '+product+'; buildConfigurationList = '+appconfig+'; buildPhases = '+items(phases)+'; buildRules = (); dependencies = ();}')
proxy=add('proxy','{isa = PBXContainerItemProxy; containerPortal = '+uid('project')+'; proxyType = 1; remoteGlobalIDString = '+app+'; remoteInfo = SwipeTennis;}')
dep=add('dependency','{isa = PBXTargetDependency; target = '+app+'; targetProxy = '+proxy+';}')
testconfig=configs('uitest',dict(common,PRODUCT_BUNDLE_IDENTIFIER='com.swipetennis.app.uitests',PRODUCT_NAME='"$(TARGET_NAME)"',GENERATE_INFOPLIST_FILE='YES',TEST_TARGET_NAME='SwipeTennis'))
add('uitest','{isa = PBXNativeTarget; name = SwipeTennisUITests; productName = SwipeTennisUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = '+testproduct+'; buildConfigurationList = '+testconfig+'; buildPhases = '+items([phase('testsource','PBXSourcesBuildPhase',[uibuild]),phase('testframework','PBXFrameworksBuildPhase',[])])+'; buildRules = (); dependencies = '+items([dep])+';}')
projectconfig=configs('project',{'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','DEBUG_INFORMATION_FORMAT':'dwarf'})
add('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 1600; TargetAttributes = {'+app+' = {CreatedOnToolsVersion = 16.0;}; '+test+' = {CreatedOnToolsVersion = 16.0; TestTargetID = '+app+';};};}; buildConfigurationList = '+projectconfig+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = '+group+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+items([app,test])+';}')
(root/'SwipeTennis.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+uid('project')+';}\n')
def ref(id,name): return '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+id+'" BuildableName="'+name+'" BlueprintName="'+name.split('.')[0]+'" ReferencedContainer="container:SwipeTennis.xcodeproj"/>'
scheme='''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">APP</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">TEST</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">APP</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">APP</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'SwipeTennis.xcodeproj/xcshareddata/xcschemes/SwipeTennis.xcscheme').write_text(scheme.replace('APP',ref(app,'SwipeTennis.app')).replace('TEST',ref(test,'SwipeTennisUITests.xctest')))
print('Generated SwipeTennis.xcodeproj')
