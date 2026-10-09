#!/usr/bin/env python3
import pathlib, hashlib, plistlib, json
root = pathlib.Path(__file__).resolve().parent.parent
project = root / 'Gravix.xcodeproj'
project.mkdir(exist_ok=True)
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def quoted(s): return json.dumps(str(s), ensure_ascii=False)
objects = []
def obj(key, content): objects.append(f'{uid(key)} = {{ {content} }};')
source_files = sorted(str(p.relative_to(root)) for p in (root / 'Sources').rglob('*') if p.suffix in ['.swift', '.mm'])
resource_files = sorted(str(p.relative_to(root)) for p in (root / 'Resources').iterdir() if p.suffix in ['.txt', '.icns'])
for path in source_files + resource_files:
    kind = 'sourcecode.swift' if path.endswith('.swift') else 'sourcecode.cpp.objcpp' if path.endswith('.mm') else 'image.icns' if path.endswith('.icns') else 'text'
    obj(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;')
    obj('build:'+path, f'isa = PBXBuildFile; fileRef = {uid(path)};')
obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Gravix.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('sources', 'isa = PBXGroup; name = Sources; children = (' + ','.join(uid(p) for p in source_files) + '); sourceTree = "<group>";')
obj('resources', 'isa = PBXGroup; name = Resources; children = (' + ','.join(uid(p) for p in resource_files) + '); sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; name = Products; children = ({uid("app")}); sourceTree = "<group>";')
obj('main', f'isa = PBXGroup; children = ({uid("sources")},{uid("resources")},{uid("products")}); sourceTree = "<group>";')
obj('sourcePhase', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(uid('build:'+p) for p in source_files) + '); runOnlyForDeploymentPostprocessing = 0;')
obj('resourcePhase', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(uid('build:'+p) for p in resource_files) + '); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworkPhase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
shell = '/usr/bin/python3 "$SRCROOT/Scripts/bundle-libraries.py"'
obj('bundlePhase', f'isa = PBXShellScriptBuildPhase; name = "Bundle RDP runtime"; buildActionMask = 2147483647; alwaysOutOfDate = 1; files = (); inputPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; shellScript = {quoted(shell)};')
base = {
    'PRODUCT_NAME':'Gravix', 'PRODUCT_BUNDLE_IDENTIFIER':'com.gravix.desktop',
    'INFOPLIST_FILE':'Resources/Info.plist', 'MACOSX_DEPLOYMENT_TARGET':'14.0',
    'SWIFT_VERSION':'5.0', 'CLANG_CXX_LANGUAGE_STANDARD':'c++17', 'CLANG_ENABLE_OBJC_ARC':'YES',
    'CLANG_ENABLE_MODULES':'YES', 'SWIFT_OBJC_BRIDGING_HEADER':'Sources/RDPBridge/GravixRDP.h',
    'HEADER_SEARCH_PATHS':['$(SRCROOT)/Vendor/include/freerdp3','$(SRCROOT)/Vendor/include/winpr3'],
    'LIBRARY_SEARCH_PATHS':['$(SRCROOT)/Vendor/lib'],
    'OTHER_LDFLAGS':['-lfreerdp-client3','-lfreerdp3','-lwinpr3','-lc++','-framework','QuartzCore','-framework','Security'],
    'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks'],
    'ENABLE_USER_SCRIPT_SANDBOXING':'NO', 'ENABLE_APP_SANDBOX':'NO', 'ENABLE_HARDENED_RUNTIME':'YES',
    'CODE_SIGN_ENTITLEMENTS':'Resources/Gravix.entitlements', 'CODE_SIGN_IDENTITY':'-', 'CODE_SIGN_STYLE':'Manual', 'ARCHS':'arm64', 'ONLY_ACTIVE_ARCH':'YES',
    'COMBINE_HIDPI_IMAGES':'YES', 'SWIFT_EMIT_LOC_STRINGS':'NO', 'GENERATE_INFOPLIST_FILE':'NO',
}
for mode in ['Debug','Release']:
    settings = dict(base)
    settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
    settings['GCC_OPTIMIZATION_LEVEL'] = '0' if mode == 'Debug' else 's'
    settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'
    def val(v): return '(' + ','.join(quoted(x) for x in v) + ')' if isinstance(v,list) else quoted(v)
    obj(mode, 'isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {' + ''.join(k+' = '+val(v)+';' for k,v in settings.items()) + '};')
    obj('project'+mode, 'isa = XCBuildConfiguration; name = '+mode+'; buildSettings = { SDKROOT = macosx; };')
obj('targetConfig', f'isa = XCConfigurationList; buildConfigurations = ({uid("Debug")},{uid("Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
obj('projectConfig', f'isa = XCConfigurationList; buildConfigurations = ({uid("projectDebug")},{uid("projectRelease")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetConfig")}; buildPhases = ({uid("sourcePhase")},{uid("frameworkPhase")},{uid("resourcePhase")},{uid("bundlePhase")}); buildRules = (); dependencies = (); name = Gravix; productName = Gravix; productReference = {uid("app")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700; }}; buildConfigurationList = {uid("projectConfig")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en,"zh-Hans",Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + '\n}; rootObject = '+uid('project')+'; }\n')
schemes = project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="Gravix.app" BlueprintName="Gravix" ReferencedContainer="container:Gravix.xcodeproj"/>'
(schemes/'Gravix.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
info = {'CFBundleExecutable':'Gravix','CFBundleIdentifier':'com.gravix.desktop','CFBundleName':'Gravix','CFBundleDisplayName':'Gravix','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.1','CFBundleVersion':'3','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','CFBundleIconFile':'AppIcon','NSLocalNetworkUsageDescription':'连接你指定的 Windows 远程桌面电脑。','LSApplicationCategoryType':'public.app-category.productivity'}
(root/'Resources/Info.plist').write_bytes(plistlib.dumps(info))
