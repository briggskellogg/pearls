#!/usr/bin/env python3
"""Rebuild the dependency-free Xcode project from checked-in sources.

No package downloads or Apple credentials are needed to generate this file.
Xcode and an Apple SDK are still required to compile it.
"""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Pearls.xcodeproj"
OBJECTS = {}


def identifier(label):
    return hashlib.sha1(label.encode("utf-8")).hexdigest()[:24].upper()


def add(label, isa, **fields):
    key = identifier(label)
    if key in OBJECTS:
        raise ValueError(f"Duplicate project object: {label}")
    OBJECTS[key] = {"isa": isa, **fields}
    return key


def encode(value, depth=0):
    tab = "\t" * depth
    if isinstance(value, dict):
        inner = "\n".join(f"{tab}\t{json.dumps(str(k))} = {encode(v, depth + 1)};" for k, v in value.items())
        return "{\n" + inner + "\n" + tab + "}"
    if isinstance(value, list):
        return "(\n" + "\n".join(f"{tab}\t{encode(v, depth + 1)}," for v in value) + "\n" + tab + ")"
    return json.dumps(str(value), ensure_ascii=False)


app_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Pearls").rglob("*.swift"))
share_sources = ["Pearls/Platform/AppPaths.swift", "PearlsShare/ShareViewController.swift"]
resources = ["Pearls/Resources/Assets.xcassets", "Pearls/Resources/PrivacyInfo.xcprivacy"]
resources += sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Pearls/Resources/Fonts").iterdir()
                    if p.is_file() and p.suffix.lower() in {".otf", ".ttf"})
share_resources = ["PearlsShare/PrivacyInfo.xcprivacy"]
configuration_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "Configuration").iterdir() if p.is_file() and p.name != "Local.xcconfig")
support_files = ["BuildSupport/prepare-assets.sh", "BuildSupport/PrepareIcons.swift", "BuildSupport/generate-project.py"]
all_files = sorted(set(app_sources + share_sources + resources + share_resources + configuration_files + support_files))
missing_files = [path for path in all_files if not (ROOT / path).exists()]
if missing_files:
    raise FileNotFoundError("Missing project inputs: " + ", ".join(missing_files))
file_refs = {}


def file_type(path):
    suffix = Path(path).suffix
    return {".swift": "sourcecode.swift", ".xcassets": "folder.assetcatalog", ".plist": "text.plist.xml",
            ".entitlements": "text.plist.entitlements", ".xcprivacy": "text.xml", ".xcconfig": "text.xcconfig",
            ".otf": "file", ".ttf": "file", ".py": "text.script.python", ".sh": "text.script.sh"}.get(suffix, "text")


for path in all_files:
    file_refs[path] = add("file:" + path, "PBXFileReference", lastKnownFileType=file_type(path),
                          path=path, sourceTree="SOURCE_ROOT")

groups = []
for folder in ["Pearls", "PearlsShare", "Configuration", "BuildSupport"]:
    groups.append(add("group:" + folder, "PBXGroup", name=folder,
                      children=[file_refs[p] for p in all_files if p.startswith(folder + "/")], sourceTree="<group>"))

package_ref = add("local-package", "XCLocalSwiftPackageReference", relativePath="Packages/PearlsCore")
package_group = add("package-file", "PBXFileReference", lastKnownFileType="folder",
                    path="Packages/PearlsCore", sourceTree="SOURCE_ROOT")
groups.append(add("group:Packages", "PBXGroup", name="Packages", children=[package_group], sourceTree="<group>"))

product_refs = {}
for target in ["Pearls-Mac", "Pearls-iOS", "PearlsShare"]:
    is_extension = target == "PearlsShare"
    product_refs[target] = add("product:" + target, "PBXFileReference",
        explicitFileType="wrapper.app-extension" if is_extension else "wrapper.application",
        includeInIndex="0", path="PearlsShare.appex" if is_extension else "Pearls.app", sourceTree="BUILT_PRODUCTS_DIR")
products_group = add("group:Products", "PBXGroup", name="Products", children=list(product_refs.values()), sourceTree="<group>")
main_group = add("group:Main", "PBXGroup", children=groups + [products_group], sourceTree="<group>")


def configurations(label, settings, base=False):
    refs = []
    for mode in ["Debug", "Release"]:
        values = dict(settings)
        if mode == "Debug":
            values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone", "DEBUG_INFORMATION_FORMAT": "dwarf",
                           "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG", "ONLY_ACTIVE_ARCH": "YES"})
        else:
            values.update({"SWIFT_OPTIMIZATION_LEVEL": "-O", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                           "SWIFT_COMPILATION_MODE": "wholemodule"})
        extra = {"baseConfigurationReference": file_refs["Configuration/Shared.xcconfig"]} if base else {}
        refs.append(add(f"config:{label}:{mode}", "XCBuildConfiguration", buildSettings=values, name=mode, **extra))
    return add("config-list:" + label, "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


project_config = configurations("project", {
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_WARN_UNUSED_VARIABLE": "YES", "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES", "DEVELOPMENT_LANGUAGE": "en",
    "MACOSX_DEPLOYMENT_TARGET": "14.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0"
}, base=True)

target_ids = {name: identifier("target:" + name) for name in product_refs}


def build_phase(target, name, isa, paths):
    refs = [add(f"build:{target}:{name}:{path}", "PBXBuildFile", fileRef=file_refs[path]) for path in paths]
    return add(f"phase:{target}:{name}", isa, buildActionMask="2147483647", files=refs, runOnlyForDeploymentPostprocessing="0")


for target in ["PearlsShare", "Pearls-Mac", "Pearls-iOS"]:
    is_mac = target == "Pearls-Mac"
    is_extension = target == "PearlsShare"
    source_paths = share_sources if is_extension else app_sources
    resource_paths = share_resources if is_extension else resources
    sources_phase = build_phase(target, "Sources", "PBXSourcesBuildPhase", source_paths)
    resources_phase = build_phase(target, "Resources", "PBXResourcesBuildPhase", resource_paths)
    package_products = []
    framework_files = []
    if not is_extension:
        dependency = add("package-product:" + target, "XCSwiftPackageProductDependency", package=package_ref, productName="PearlsCore")
        package_products.append(dependency)
        framework_files.append(add("framework:" + target, "PBXBuildFile", productRef=dependency))
    frameworks_phase = add("phase:" + target + ":Frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647",
                           files=framework_files, runOnlyForDeploymentPostprocessing="0")
    phases = []
    if not is_extension:
        phases.append(add("phase:" + target + ":Icons", "PBXShellScriptBuildPhase", buildActionMask="2147483647",
            name="Package supplied app icon", files=[], alwaysOutOfDate="1", inputPaths=["$(SRCROOT)/BuildSupport/prepare-assets.sh", "$(SRCROOT)/BuildSupport/PrepareIcons.swift", "$(SRCROOT)/Pearls/Resources/Assets.xcassets/PearlsSymbol.imageset/pearls-symbol.png", "$(SRCROOT)/Pearls/Resources/Assets.xcassets/MakerMark.imageset/maker-mark.png"],
            outputPaths=["$(SRCROOT)/Pearls/Resources/Assets.xcassets/AppIcon-Mac.appiconset/Contents.json", "$(SRCROOT)/Pearls/Resources/Assets.xcassets/AppIcon-iOS.appiconset/Contents.json"],
            runOnlyForDeploymentPostprocessing="0", shellPath="/bin/bash", shellScript='bash "$SRCROOT/BuildSupport/prepare-assets.sh"\n'))
    phases += [sources_phase, frameworks_phase, resources_phase]
    dependencies = []
    if target == "Pearls-iOS":
        proxy = add("share-proxy", "PBXContainerItemProxy", containerPortal=identifier("project"), proxyType="1",
                    remoteGlobalIDString=target_ids["PearlsShare"], remoteInfo="PearlsShare")
        dependencies.append(add("share-dependency", "PBXTargetDependency", target=target_ids["PearlsShare"], targetProxy=proxy))
        embed = add("embed-share-file", "PBXBuildFile", fileRef=product_refs["PearlsShare"], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(add("embed-share-phase", "PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath="", dstSubfolderSpec="13",
                          files=[embed], name="Embed Share Extension", runOnlyForDeploymentPostprocessing="0"))
    settings = {
        "PRODUCT_NAME": "PearlsShare" if is_extension else "Pearls",
        "PRODUCT_BUNDLE_IDENTIFIER": "$(PEARLS_BUNDLE_ID_BASE).share" if is_extension else "$(PEARLS_BUNDLE_ID_BASE)",
        "SDKROOT": "macosx" if is_mac else "iphoneos",
        "SUPPORTED_PLATFORMS": "macosx" if is_mac else "iphoneos iphonesimulator",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Configuration/Mac-Info.plist" if is_mac else "Configuration/Share-Info.plist" if is_extension else "Configuration/iOS-Info.plist",
        "CODE_SIGN_ENTITLEMENTS": "Configuration/" + target + ".entitlements",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks" if is_mac else "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks" if is_extension else "$(inherited) @executable_path/Frameworks",
        "ENABLE_PREVIEWS": "YES", "SWIFT_VERSION": "5.0", "SKIP_INSTALL": "YES" if is_extension else "NO"
    }
    if is_mac:
        settings.update({"ENABLE_HARDENED_RUNTIME": "YES", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon-Mac", "COMBINE_HIDPI_IMAGES": "YES"})
    else:
        settings.update({"TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO"})
        if is_extension:
            settings.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "PRODUCT_MODULE_NAME": "PearlsShare"})
        else:
            settings.update({"ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon-iOS"})
    configuration_list = configurations(target, settings)
    add("target:" + target, "PBXNativeTarget", buildConfigurationList=configuration_list, buildPhases=phases,
        buildRules=[], dependencies=dependencies, name=target, packageProductDependencies=package_products,
        productName=settings["PRODUCT_NAME"], productReference=product_refs[target],
        productType="com.apple.product-type.app-extension" if is_extension else "com.apple.product-type.application")

project_id = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600",
    "TargetAttributes": {target_ids[name]: {"CreatedOnToolsVersion": "26.0", "ProvisioningStyle": "Automatic"} for name in target_ids}},
    buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings="0",
    knownRegions=["en", "Base"], mainGroup=main_group, packageReferences=[package_ref], productRefGroup=products_group,
    projectDirPath="", projectRoot="", targets=[target_ids[name] for name in ["Pearls-Mac", "Pearls-iOS", "PearlsShare"]])

# All references must exist; filenames must be real before a release package is created.
for obj in OBJECTS.values():
    for key in ["fileRef", "productRef", "target", "targetProxy", "containerPortal", "productReference", "buildConfigurationList", "mainGroup", "productRefGroup", "package", "baseConfigurationReference"]:
        if key in obj:
            assert obj[key] in OBJECTS, (key, obj[key])
    for key in ["children", "files", "buildPhases", "dependencies", "packageProductDependencies", "targets", "packageReferences", "buildConfigurations"]:
        for ref in obj.get(key, []):
            assert ref in OBJECTS, (key, ref)

PROJECT.mkdir(exist_ok=True)
tree = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": OBJECTS, "rootObject": project_id}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(tree) + "\n", encoding="utf-8")

scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def buildable(parent, name):
    ET.SubElement(parent, "BuildableReference", {"BuildableIdentifier": "primary", "BlueprintIdentifier": target_ids[name],
        "BuildableName": "Pearls.app", "BlueprintName": name, "ReferencedContainer": "container:Pearls.xcodeproj"})


for name in ["Pearls-Mac", "Pearls-iOS"]:
    scheme = ET.Element("Scheme", {"LastUpgradeVersion": "2600", "version": "1.7"})
    action = ET.SubElement(scheme, "BuildAction", {"parallelizeBuildables": "YES", "buildImplicitDependencies": "YES"})
    entries = ET.SubElement(action, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", {key: "YES" for key in ["buildForTesting", "buildForRunning", "buildForProfiling", "buildForArchiving", "buildForAnalyzing"]})
    buildable(entry, name)
    ET.SubElement(scheme, "TestAction", {"buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB", "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB", "shouldUseLaunchSchemeArgsEnv": "YES"})
    launch = ET.SubElement(scheme, "LaunchAction", {"buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB", "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB", "launchStyle": "0", "useCustomWorkingDirectory": "NO", "ignoresPersistentStateOnLaunch": "NO", "debugDocumentVersioning": "YES", "debugServiceExtension": "internal", "allowLocationSimulation": "YES"})
    buildable(ET.SubElement(launch, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}), name)
    profile = ET.SubElement(scheme, "ProfileAction", {"buildConfiguration": "Release", "shouldUseLaunchSchemeArgsEnv": "YES", "savedToolIdentifier": "", "useCustomWorkingDirectory": "NO", "debugDocumentVersioning": "YES"})
    buildable(ET.SubElement(profile, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}), name)
    ET.SubElement(scheme, "AnalyzeAction", {"buildConfiguration": "Debug"})
    ET.SubElement(scheme, "ArchiveAction", {"buildConfiguration": "Release", "revealArchiveInOrganizer": "YES"})
    ET.indent(scheme, space="  ")
    ET.ElementTree(scheme).write(scheme_dir / (name + ".xcscheme"), encoding="UTF-8", xml_declaration=True)

workspace = PROJECT / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
print(f"Generated {PROJECT.name}: {len(app_sources)} shared app sources, 3 targets, 2 shared schemes, local PearlsCore package.")
