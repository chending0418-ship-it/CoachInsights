#!/usr/bin/env python3
"""Generate the Universal Xcode project with pinned local MediaPipe package."""
from pathlib import Path
import hashlib
import json
from mediapipe_static_packaging import NAMES

ROOT = Path(__file__).resolve().parents[1]
def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = {}
def add(name, value):
    objects[ident(name)] = value
    return ident(name)
def ref(name):
    return ident(name)
def array(values):
    return "(" + ", ".join(values) + ",)"
targets = ["CoachInsights", "CoachInsightsTests", "CoachInsightsUITests"]
buildConfig = add("BuildConfig", '{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Build.xcconfig; sourceTree = "<group>"; }')
signingExample = add("SigningExample", '{isa = PBXFileReference; lastKnownFileType = text; path = Signing.local.xcconfig.example; sourceTree = "<group>"; }')
add("ConfigGroup", f'{{isa = PBXGroup; children = {array([buildConfig, signingExample])}; path = Config; sourceTree = "<group>"; }}')
package = add("PosePackage", '{isa = XCLocalSwiftPackageReference; relativePath = Packages/MediaPipeTasks; }')
poseProduct = add("PoseProduct", f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = MediaPipeTasksVision; }}')
poseBuild = add("PoseBuild", f'{{isa = PBXBuildFile; productRef = {poseProduct}; }}')
packaging_script = '''set -eu
/usr/bin/python3 "${SRCROOT}/scripts/mediapipe_static_packaging.py" --app "${TARGET_BUILD_DIR}/${WRAPPER_NAME}" --built-products "${BUILT_PRODUCTS_DIR}" --report "${DERIVED_FILE_DIR}/mediapipe-static-packaging.json"
'''
packaging_inputs = ["$(SRCROOT)/scripts/mediapipe_static_packaging.py", "$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)"]
packaging_inputs += [f"$(TARGET_BUILD_DIR)/$(FRAMEWORKS_FOLDER_PATH)/{name}.framework/{name}" for name in NAMES]
packaging_inputs += [f"$(BUILT_PRODUCTS_DIR)/{name}.framework/{name}" for name in NAMES]
staticPackaging = add("StaticMediaPipePackaging", '{isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); inputPaths = ' + array([json.dumps(path) for path in packaging_inputs]) + '; outputPaths = ("$(DERIVED_FILE_DIR)/mediapipe-static-packaging.json",); name = "Remove empty statically linked MediaPipe wrappers"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = ' + json.dumps(packaging_script) + '; }')
product = {}
for name in targets:
    (ROOT / name).mkdir(exist_ok=True)
    app = name == "CoachInsights"
    product[name] = add(name+"Product", f'{{isa = PBXFileReference; explicitFileType = {"wrapper.application" if app else "wrapper.cfbundle"}; path = {name}.{"app" if app else "xctest"}; sourceTree = BUILT_PRODUCTS_DIR; }}')
    add(name+"Group", f'{{isa = PBXFileSystemSynchronizedRootGroup; path = {name}; sourceTree = "<group>"; }}')
    for phase in ["Sources", "Frameworks", "Resources"]:
        add(name+phase, f'{{isa = PBX{phase}BuildPhase; buildActionMask = 2147483647; files = {array([poseBuild]) if app and phase == "Frameworks" else "()"}; runOnlyForDeploymentPostprocessing = 0; }}')
    for config in ["Debug", "Release"]:
        settings = {
            "PRODUCT_BUNDLE_IDENTIFIER": '"$(COACH_INSIGHTS_BUNDLE_IDENTIFIER)"' if app else f"com.coachinsights.{name}",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"', "CODE_SIGN_STYLE": "Automatic",
            "GENERATE_INFOPLIST_FILE": "NO" if app else "YES",
            "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        }
        if app:
            settings["INFOPLIST_FILE"] = "Config/Info.plist"
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
            settings["SKIP_INSTALL"] = "NO"
            # This post-embed phase verifies and removes only empty wrappers in
            # the built app before CodeSign. Xcode's script sandbox cannot model
            # modifying copy-phase outputs without a duplicate-producer cycle.
            settings["ENABLE_USER_SCRIPT_SANDBOXING"] = "NO"
        elif name == "CoachInsightsTests":
            settings["TEST_HOST"] = '"$(BUILT_PRODUCTS_DIR)/CoachInsights.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CoachInsights"'
            settings["BUNDLE_LOADER"] = '"$(TEST_HOST)"'
        else:
            settings["TEST_TARGET_NAME"] = "CoachInsights"
        if config == "Debug":
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = '"DEBUG $(inherited)"'
        add(name+config, '{isa = XCBuildConfiguration; buildSettings = {' +
            " ".join(f"{key} = {value};" for key,value in settings.items()) + f'}}; name = {config}; }}')
    add(name+"Configs", f'{{isa = XCConfigurationList; buildConfigurations = {array([ref(name+"Debug"),ref(name+"Release")])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
    dependencies = []
    if not app:
        proxy = add(name+"Proxy", f'{{isa = PBXContainerItemProxy; containerPortal = {ref("Project")}; proxyType = 1; remoteGlobalIDString = {ref("CoachInsightsTarget")}; remoteInfo = CoachInsights; }}')
        dependencies.append(add(name+"Dependency", f'{{isa = PBXTargetDependency; target = {ref("CoachInsightsTarget")}; targetProxy = {proxy}; }}'))
    kind = "application" if app else "bundle.unit-test" if name == "CoachInsightsTests" else "bundle.ui-testing"
    phases = [ref(name+p) for p in ["Sources", "Frameworks", "Resources"]] + ([staticPackaging] if app else [])
    add(name+"Target", f'{{isa = PBXNativeTarget; buildConfigurationList = {ref(name+"Configs")}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies) if dependencies else "()"}; fileSystemSynchronizedGroups = ({ref(name+"Group")},); packageProductDependencies = {array([poseProduct]) if app else "()"}; name = {name}; productName = {name}; productReference = {product[name]}; productType = "com.apple.product-type.{kind}"; }}')
add("Products", f'{{isa = PBXGroup; children = {array(list(product.values()))}; name = Products; sourceTree = "<group>"; }}')
add("MainGroup", f'{{isa = PBXGroup; children = {array([ref(n+"Group") for n in targets]+[ref("ConfigGroup"), ref("Products")])}; sourceTree = "<group>"; }}')
for config in ["Debug", "Release"]:
    settings = '"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = x86_64; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; ENABLE_USER_SCRIPT_SANDBOXING = YES;'
    settings += ' DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)"); ONLY_ACTIVE_ARCH = YES;' if config == "Debug" else ' DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";'
    add("Project"+config, f'{{isa = XCBuildConfiguration; baseConfigurationReference = {buildConfig}; buildSettings = {{{settings}}}; name = {config}; }}')
add("ProjectConfigs", f'{{isa = XCConfigurationList; buildConfigurations = ({ref("ProjectDebug")}, {ref("ProjectRelease")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
add("Project", f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2610; }}; buildConfigurationList = {ref("ProjectConfigs")}; compatibilityVersion = "Xcode 16.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base); mainGroup = {ref("MainGroup")}; minimizedProjectReferenceProxies = 1; preferredProjectObjectVersion = 77; productRefGroup = {ref("Products")}; packageReferences = ({package},); projectDirPath = ""; projectRoot = ""; targets = {array([ref(n+"Target") for n in targets])}; }}')
project = ROOT / "CoachInsights.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 77;\nobjects = {\n" + "\n".join(f"{key} = {value};" for key,value in objects.items()) + f"\n}};\nrootObject = {ref('Project')};\n}}\n")
scheme = project / "xcshareddata/xcschemes"
scheme.mkdir(parents=True, exist_ok=True)
def buildref(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(name+"Target")}" BuildableName="{name}.{"app" if name == "CoachInsights" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:CoachInsights.xcodeproj"/>'
(scheme / "CoachInsights.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2610" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildref("CoachInsights")}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO">{buildref("CoachInsightsTests")}</TestableReference>
<TestableReference skipped="NO">{buildref("CoachInsightsUITests")}</TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref("CoachInsights")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref("CoachInsights")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
