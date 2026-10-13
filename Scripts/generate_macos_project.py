#!/usr/bin/env python3
"""Generate a native macOS target without changing the iPhone signing settings."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "MikanseiMac.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = []
def uid(name): return hashlib.sha1(("mac:" + name).encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value), ensure_ascii=False)
def obj(name, body): objects.append(f"{uid(name)} = {{ {body} }};"); return uid(name)
def ids(names): return "(" + ",".join(uid(x) for x in names) + ",)" if names else "()"
sources = sorted(ROOT.glob("Mac/*.swift")) + sorted(ROOT.glob("Sync/*.swift")) + sorted(ROOT.glob("Sources/MikanseiCore/*.swift"))
resources = sorted(ROOT.glob("Mac/Resources/*.icns"))
tests = sorted(ROOT.glob("MacUITests/*.swift"))
for path in sources + resources + tests:
    rel = path.relative_to(ROOT).as_posix()
    obj("ref:" + rel, f"isa = PBXFileReference; path = {quote(rel)}; sourceTree = SOURCE_ROOT; lastKnownFileType = {'sourcecode.swift' if path.suffix == '.swift' else 'image.icns'};")
    obj("build:" + rel, f"isa = PBXBuildFile; fileRef = {uid('ref:' + rel)};")
obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Mikansei.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj("tests-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = MikanseiMacUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj("products", f'isa = PBXGroup; name = Products; children = {ids(["product", "tests-product"])}; sourceTree = "<group>";')
obj("files", f'isa = PBXGroup; name = "Mac & Shared"; children = {ids(["ref:" + p.relative_to(ROOT).as_posix() for p in sources + resources + tests])}; sourceTree = "<group>";')
obj("root", f'isa = PBXGroup; children = {ids(["files", "products"])}; sourceTree = "<group>";')
for name, files in [("sources", sources), ("resources", resources)]:
    obj(name, f"isa = {'PBXSourcesBuildPhase' if name == 'sources' else 'PBXResourcesBuildPhase'}; buildActionMask = 2147483647; files = {ids(['build:' + p.relative_to(ROOT).as_posix() for p in files])}; runOnlyForDeploymentPostprocessing = 0;")
obj("frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
obj("tests-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {ids(['build:' + p.relative_to(ROOT).as_posix() for p in tests])}; runOnlyForDeploymentPostprocessing = 0;")
obj("tests-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
obj("proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {uid('target')}; remoteInfo = MikanseiMac;")
obj("dependency", f"isa = PBXTargetDependency; target = {uid('target')}; targetProxy = {uid('proxy')};")
settings = {
    "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "PRODUCT_NAME": "Mikansei", "PRODUCT_BUNDLE_IDENTIFIER": "com.personal.mikansei.macOS",
    "INFOPLIST_FILE": "Mac/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
    "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_ENTITLEMENTS": "Mac/MikanseiMac.entitlements",
    "MARKETING_VERSION": "0.3.0", "CURRENT_PROJECT_VERSION": "4", "COMBINE_HIDPI_IMAGES": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
}
for name in ["Debug", "Release"]:
    values = dict(settings, SWIFT_OPTIMIZATION_LEVEL="-Onone" if name == "Debug" else "-O")
    obj(name, "isa = XCBuildConfiguration; name = " + name + "; buildSettings = { " + " ".join(k + " = " + quote(v) + ";" for k,v in values.items()) + " };")
    test_values = {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0", "PRODUCT_NAME": "MikanseiMacUITests", "PRODUCT_BUNDLE_IDENTIFIER": "com.personal.mikansei.macOS.uitests", "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual", "TEST_TARGET_NAME": "MikanseiMac"}
    obj("tests-" + name, "isa = XCBuildConfiguration; name = " + name + "; buildSettings = { " + " ".join(k + " = " + quote(v) + ";" for k,v in test_values.items()) + " };")
obj("configurations", f"isa = XCConfigurationList; buildConfigurations = {ids(['Debug','Release'])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
obj("tests-configurations", f"isa = XCConfigurationList; buildConfigurations = {ids(['tests-Debug','tests-Release'])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
obj("tests-target", f'isa = PBXNativeTarget; name = MikanseiMacUITests; productName = MikanseiMacUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = {uid("tests-product")}; buildConfigurationList = {uid("tests-configurations")}; buildPhases = {ids(["tests-sources","tests-frameworks"])}; dependencies = {ids(["dependency"])}; buildRules = ();')
obj("target", f"isa = PBXNativeTarget; name = MikanseiMac; productName = Mikansei; productType = \"com.apple.product-type.application\"; productReference = {uid('product')}; buildConfigurationList = {uid('configurations')}; buildPhases = {ids(['sources','frameworks','resources'])}; dependencies = (); buildRules = ();")
obj("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; TargetAttributes = {{ {uid("tests-target")} = {{ TestTargetID = {uid("target")}; }}; }}; }}; buildConfigurationList = {uid("configurations")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; knownRegions = (zh_CN,en,Base); mainGroup = {uid("root")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = {ids(["target", "tests-target"])};')
(PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')
scheme = PROJECT / "xcshareddata/xcschemes"
scheme.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="Mikansei.app" BlueprintName="MikanseiMac" ReferencedContainer="container:MikanseiMac.xcodeproj" />'
test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("tests-target")}" BuildableName="MikanseiMacUITests.xctest" BlueprintName="MikanseiMacUITests" ReferencedContainer="container:MikanseiMac.xcodeproj" />'
(scheme / "MikanseiMac.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" />
</Scheme>''')
print(PROJECT)
