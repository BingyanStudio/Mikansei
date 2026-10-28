#!/usr/bin/env python3
"""Generate the self-contained Xcode project without third-party dependencies."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Mikansei.xcodeproj"
PROJECT.mkdir(exist_ok=True)
previous_objects = {}
if (PROJECT / "project.pbxproj").exists():
    # Keep the signing and build settings selected in Xcode when adding source files or targets.
    previous_objects = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(PROJECT / "project.pbxproj")
    ]))["objects"]

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

objects = []
def obj(name, body):
    objects.append(f"\t\t{uid(name)} = {{ {body} }};")
    return uid(name)

def quote(value):
    if isinstance(value, list):
        return "(" + ", ".join(quote(item) for item in value) + ",)" if value else "()"
    if isinstance(value, dict):
        return "{ " + " ".join(f"{quote(key)} = {quote(item)};" for key, item in value.items()) + " }"
    return json.dumps(str(value), ensure_ascii=False)

def ids(names):
    return "(" + ", ".join(uid(name) for name in names) + ",)"

core_files = sorted(ROOT.glob("Sources/MikanseiCore/*.swift"))
shared_files = sorted(ROOT.glob("Shared/*.swift"))
sync_files = sorted(ROOT.glob("Sync/*.swift"))
widget_files = sorted(ROOT.glob("Widgets/*.swift")) + core_files + shared_files
app_files = sorted(ROOT.glob("App/*.swift")) + core_files + shared_files + sync_files
test_files = sorted(ROOT.glob("UITests/*.swift"))
icon_files = sorted(
    path for path in ROOT.glob("App/Resources/*.png")
    if not path.name.startswith("AppIcon")
) + sorted(ROOT.glob("App/Resources/*.wav"))
asset_catalog = ROOT / "App/Assets.xcassets"
app_privacy_manifest = ROOT / "App/PrivacyInfo.xcprivacy"
widget_privacy_manifest = ROOT / "Widgets/PrivacyInfo.xcprivacy"
app_resource_files = icon_files + [asset_catalog, app_privacy_manifest]
widget_resource_files = [widget_privacy_manifest]
for path in sorted(set(app_files + test_files + widget_files)):
    rel = path.relative_to(ROOT).as_posix()
    obj("ref:" + rel, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = SOURCE_ROOT;")
    obj("build:" + rel, f"isa = PBXBuildFile; fileRef = {uid('ref:' + rel)};")
    if path in widget_files:
        obj("widget-build:" + rel, f"isa = PBXBuildFile; fileRef = {uid('ref:' + rel)};")
for path in app_resource_files + widget_resource_files:
    rel = path.relative_to(ROOT).as_posix()
    file_type = {
        ".wav": "audio.wav",
        ".png": "image.png",
        ".xcassets": "folder.assetcatalog",
        ".xcprivacy": "text.xml",
    }[path.suffix]
    obj("ref:" + rel, f"isa = PBXFileReference; lastKnownFileType = {quote(file_type)}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;")
    obj("build:" + rel, f"isa = PBXBuildFile; fileRef = {uid('ref:' + rel)};")
obj("plist-ref", "isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = App/Info.plist; sourceTree = SOURCE_ROOT;")
obj("widgets-plist-ref", "isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Widgets/Info.plist; sourceTree = SOURCE_ROOT;")
obj("entitlements-ref", "isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Shared/Mikansei.entitlements; sourceTree = SOURCE_ROOT;")
obj("product-app", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Mikansei.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj("product-tests", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MikanseiUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj("product-widgets", 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = MikanseiWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR;')
obj("embed-widgets-build", f"isa = PBXBuildFile; fileRef = {uid('product-widgets')}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};")
obj("embed-widgets", f"isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolderSpec = 13; files = {ids(['embed-widgets-build'])}; name = \"Embed App Extensions\"; runOnlyForDeploymentPostprocessing = 0;")
obj("resources-group", f"isa = PBXGroup; name = Resources; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in app_resource_files])}; sourceTree = \"<group>\";")
obj("app-group", f"isa = PBXGroup; name = App; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in app_files if p.parent.name == 'App'] + ['plist-ref', 'resources-group'])}; sourceTree = \"<group>\";")
obj("core-group", f"isa = PBXGroup; name = Core; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in app_files if p.parent.name == 'MikanseiCore'])}; sourceTree = \"<group>\";")
obj("test-group", f"isa = PBXGroup; name = UITests; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in test_files])}; sourceTree = \"<group>\";")
obj("widgets-group", f"isa = PBXGroup; name = Widgets; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in widget_files if p.parent.name == 'Widgets'] + ['widgets-plist-ref', 'ref:' + widget_privacy_manifest.relative_to(ROOT).as_posix()])}; sourceTree = \"<group>\";")
obj("shared-group", f"isa = PBXGroup; name = Shared; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in shared_files] + ['entitlements-ref'])}; sourceTree = \"<group>\";")
obj("sync-group", f"isa = PBXGroup; name = Sync; children = {ids(['ref:' + p.relative_to(ROOT).as_posix() for p in sync_files])}; sourceTree = \"<group>\";")
obj("products-group", f"isa = PBXGroup; name = Products; children = {ids(['product-app', 'product-widgets', 'product-tests'])}; sourceTree = \"<group>\";")
obj("main-group", f"isa = PBXGroup; children = {ids(['app-group', 'widgets-group', 'core-group', 'shared-group', 'sync-group', 'test-group', 'products-group'])}; sourceTree = \"<group>\";")
for name, files in [("app", app_files), ("tests", test_files), ("widgets", widget_files)]:
    build_prefix = "widget-build:" if name == "widgets" else "build:"
    obj(name + "-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids([build_prefix + p.relative_to(ROOT).as_posix() for p in files])}; runOnlyForDeploymentPostprocessing = 0;")
    obj(name + "-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    resource_files = app_resource_files if name == "app" else widget_resource_files if name == "widgets" else []
    resources = ids(['build:' + p.relative_to(ROOT).as_posix() for p in resource_files]) if resource_files else "()"
    obj(name + "-resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {resources}; runOnlyForDeploymentPostprocessing = 0;")

obj("test-proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('target-app')}; remoteInfo = Mikansei;")
obj("test-dependency", f"isa = PBXTargetDependency; target = {uid('target-app')}; targetProxy = {uid('test-proxy')};")
obj("widget-proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('target-widgets')}; remoteInfo = MikanseiWidgets;")
obj("widget-dependency", f"isa = PBXTargetDependency; target = {uid('target-widgets')}; targetProxy = {uid('widget-proxy')};")

common = {
    "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
}
app_settings = {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.personal.mikansei",
    "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "App/Info.plist", "INFOPLIST_KEY_CFBundleDisplayName": "Mikansei",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "CODE_SIGN_STYLE": "Automatic", "MARKETING_VERSION": "0.3.2", "CURRENT_PROJECT_VERSION": "6",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks", "SWIFT_EMIT_LOC_STRINGS": "YES",
}
widget_settings = {
    "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "Widgets/Info.plist",
    "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO", "CODE_SIGN_STYLE": "Automatic", "SKIP_INSTALL": "YES",
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
test_settings = {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.personal.qingdanji.uitests",
    "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2",
    "TEST_TARGET_NAME": "Mikansei", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
}
for scope, settings in [("project", common), ("app", app_settings), ("tests", test_settings), ("widgets", widget_settings)]:
    for configuration in ["Debug", "Release"]:
        values = dict(settings)
        if scope == "project":
            values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym"})
            if configuration == "Debug":
                values.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES"})
        values.update(previous_objects.get(uid(scope + "-" + configuration), {}).get("buildSettings", {}))
        if scope == "app":
            values.update({
                "CODE_SIGN_ENTITLEMENTS": "Shared/Mikansei.entitlements",
                "MIKANSEI_SHARED_KEYCHAIN_SUFFIX": "$(PRODUCT_BUNDLE_IDENTIFIER).shared",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            })
        if scope == "widgets":
            host = dict(app_settings)
            host.update(previous_objects.get(uid("app-" + configuration), {}).get("buildSettings", {}))
            if not values.get("PRODUCT_BUNDLE_IDENTIFIER", "").startswith(host["PRODUCT_BUNDLE_IDENTIFIER"] + "."):
                values["PRODUCT_BUNDLE_IDENTIFIER"] = host["PRODUCT_BUNDLE_IDENTIFIER"] + ".widgets"
            for key in ["DEVELOPMENT_TEAM", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION"]:
                if key in host: values[key] = host[key]
            values.update({"CODE_SIGN_ENTITLEMENTS": "Shared/Mikansei.entitlements",
                           "MIKANSEI_HOST_BUNDLE_IDENTIFIER": host["PRODUCT_BUNDLE_IDENTIFIER"],
                           "MIKANSEI_SHARED_KEYCHAIN_SUFFIX": "$(MIKANSEI_HOST_BUNDLE_IDENTIFIER).shared"})
        body = " ".join(f"{key} = {quote(value)};" for key, value in values.items())
        obj(scope + "-" + configuration, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {configuration};")
    obj(scope + "-configs", f"isa = XCConfigurationList; buildConfigurations = {ids([scope + '-Debug', scope + '-Release'])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

for target, product_name, product_type in [("app", "Mikansei", "com.apple.product-type.application"), ("tests", "MikanseiUITests", "com.apple.product-type.bundle.ui-testing"), ("widgets", "MikanseiWidgets", "com.apple.product-type.app-extension")]:
    dependencies = ids(["test-dependency"]) if target == "tests" else ids(["widget-dependency"]) if target == "app" else "()"
    phases = [target + '-sources', target + '-frameworks', target + '-resources'] + (['embed-widgets'] if target == 'app' else [])
    obj("target-" + target, f"isa = PBXNativeTarget; buildConfigurationList = {uid(target + '-configs')}; buildPhases = {ids(phases)}; buildRules = (); dependencies = {dependencies}; name = {product_name}; productName = {product_name}; productReference = {uid('product-' + target)}; productType = {quote(product_type)};")

attributes = previous_objects.get(uid("project"), {}).get("attributes", {"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600"})
target_attributes = attributes.setdefault("TargetAttributes", {})
target_attributes.setdefault(uid("target-app"), {"CreatedOnToolsVersion": "26.0"})
target_attributes.setdefault(uid("target-tests"), {"CreatedOnToolsVersion": "26.0", "TestTargetID": uid("target-app")})
target_attributes.setdefault(uid("target-widgets"), {"CreatedOnToolsVersion": "26.0"})
obj("project", f'isa = PBXProject; attributes = {quote(attributes)}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = {uid("main-group")}; productRefGroup = {uid("products-group")}; projectDirPath = ""; projectRoot = ""; targets = {ids(["target-app", "target-tests", "target-widgets"])};')
content = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n'
(PROJECT / "project.pbxproj").write_text(content)

scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
def reference(target, name, extension):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target-" + target)}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:Mikansei.xcodeproj" />'
app_ref = reference("app", "Mikansei", "app")
test_ref = reference("tests", "MikanseiUITests", "xctest")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug" />
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" />
</Scheme>
'''
(scheme_dir / "Mikansei.xcscheme").write_text(scheme)
print(PROJECT)
