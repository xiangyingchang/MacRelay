#!/usr/bin/env python3
"""Generate a minimal Xcode project for MacRelay iOS app with local Swift package deps."""
import os, hashlib

ROOT = "/private/tmp/MacRelay"
APPS = os.path.join(ROOT, "Apps", "MacRelayiOSApp")
PROJ = os.path.join(APPS, "MacRelayiOSApp.xcodeproj")
SRC = os.path.join(APPS, "Sources")
os.makedirs(PROJ, exist_ok=True)
os.makedirs(SRC, exist_ok=True)

def gid(s):
    h = hashlib.sha1(s.encode()).hexdigest()[:24].upper()
    return h[:8] + h[8:12] + h[12:16] + h[16:20] + h[20:24]

# IDs
P = gid("project")
MG = gid("maingroup")
PG = gid("products")
SG = gid("sources")
SPMG = gid("spmgroup")
AT = gid("apptarget")
APF = gid("appproductfile")
AEB = gid("appentrybuild")
AEF = gid("appentryfile")
IPF = gid("infoplist")
DC = gid("debugconfig")
RC = gid("releaseconfig")
CLP = gid("configlistproject")
CLT = gid("configlisttarget")
SPH = gid("sourcebuildphase")
FPH = gid("frameworksphase")
RPH = gid("resourcesphase")
AD = gid("appdebug")
AR = gid("apprelease")

# Local Swift Package Reference
LPR = gid("localpkgref")
# Package product dependencies (one per product)
PDC = gid("pkgdepcore")
PDI = gid("pkgdepio")
PDS = gid("pkgdepios")
# Build file refs for package products
BFC = gid("buildfilecore")
BFI = gid("buildfileio")
BFS = gid("buildfileios")

pbxproj = os.path.join(PROJ, "project.pbxproj")
with open(pbxproj, "w") as f:
    f.write(f"""// !$*UTF8*$!
{{
    archiveVersion = 1;
    classes = {{}};
    objectVersion = 60;
    objects = {{

/* Begin PBXBuildFile section */
        {AEB} /* AppEntry.swift */ = {{isa = PBXBuildFile; fileRef = {AEF}; }};
        {BFC} /* AgentClientCore */ = {{isa = PBXBuildFile; productRef = {PDC}; }};
        {BFI} /* AgentClientIO */ = {{isa = PBXBuildFile; productRef = {PDI}; }};
        {BFS} /* AgentClientiOS */ = {{isa = PBXBuildFile; productRef = {PDS}; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
        {AEF} /* AppEntry.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppEntry.swift; sourceTree = "<group>"; }};
        {IPF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
        {APF} /* MacRelayiOSApp.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacRelayiOSApp.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXGroup section */
        {MG} = {{
            isa = PBXGroup;
            children = (
                {SG} /* Sources */,
                {SPMG} /* Packages */,
                {PG} /* Products */,
            );
            sourceTree = "<group>";
        }};
        {SG} = {{
            isa = PBXGroup;
            children = ({AEF}, {IPF});
            path = Sources;
            sourceTree = "<group>";
        }};
        {SPMG} = {{
            isa = PBXGroup;
            children = ();
            name = Packages;
            sourceTree = SOURCE_ROOT;
        }};
        {PG} = {{
            isa = PBXGroup;
            children = ({APF});
            name = Products;
            sourceTree = "<group>";
        }};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
        {AT} = {{
            isa = PBXNativeTarget;
            buildConfigurationList = {CLT};
            buildPhases = ({SPH}, {FPH}, {RPH});
            buildRules = ();
            dependencies = ();
            name = MacRelayiOSApp;
            packageProductDependencies = ({PDC}, {PDI}, {PDS});
            productName = MacRelayiOSApp;
            productReference = {APF};
            productType = "com.apple.product-type.application";
        }};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
        {P} = {{
            isa = PBXProject;
            attributes = {{
                BuildIndependentTargetsInParallel = 1;
                LastSwiftUpdateCheck = 1620;
                LastUpgradeCheck = 1620;
            }};
            buildConfigurationList = {CLP};
            compatibilityVersion = "Xcode 14.0";
            developmentRegion = en;
            hasScannedForEncodings = 0;
            knownRegions = (en, Base);
            mainGroup = {MG};
            packageReferences = ({LPR});
            productRefGroup = {PG};
            projectDirPath = "";
            projectRoot = "";
            targets = ({AT});
        }};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
        {SPH} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({AEB}); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXSourcesBuildPhase section */

/* Begin PBXFrameworksBuildPhase section */
        {FPH} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({BFC}, {BFI}, {BFS}); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXResourcesBuildPhase section */
        {RPH} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXResourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
        {DC} = {{
            isa = XCBuildConfiguration;
            buildSettings = {{
                ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;
                COPY_PHASE_STRIP = NO; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES;
                ENABLE_USER_SCRIPT_SANDBOXING = NO; GCC_DYNAMIC_NO_PIC = NO; GCC_OPTIMIZATION_LEVEL = 0;
                IPHONEOS_DEPLOYMENT_TARGET = 17.0; ONLY_ACTIVE_ARCH = YES; SDKROOT = iphoneos;
                SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; SWIFT_OPTIMIZATION_LEVEL = "-Onone";
            }};
            name = Debug;
        }};
        {RC} = {{
            isa = XCBuildConfiguration;
            buildSettings = {{
                ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;
                COPY_PHASE_STRIP = NO; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
                ENABLE_NS_ASSERTIONS = NO; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos;
                SWIFT_COMPILATION_MODE = wholemodule; VALIDATE_PRODUCT = YES;
            }};
            name = Release;
        }};
        {AD} = {{
            isa = XCBuildConfiguration;
            buildSettings = {{
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = "";
                INFOPLIST_FILE = Sources/Info.plist;
                IPHONEOS_DEPLOYMENT_TARGET = 17.0;
                LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");
                MARKETING_VERSION = 0.1.0;
                PRODUCT_BUNDLE_IDENTIFIER = com.xiangyingchang.macrelay;
                PRODUCT_NAME = MacRelayiOSApp;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            }};
            name = Debug;
        }};
        {AR} = {{
            isa = XCBuildConfiguration;
            buildSettings = {{
                CODE_SIGN_STYLE = Automatic;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = "";
                INFOPLIST_FILE = Sources/Info.plist;
                IPHONEOS_DEPLOYMENT_TARGET = 17.0;
                LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");
                MARKETING_VERSION = 0.1.0;
                PRODUCT_BUNDLE_IDENTIFIER = com.xiangyingchang.macrelay;
                PRODUCT_NAME = MacRelayiOSApp;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            }};
            name = Release;
        }};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
        {CLP} = {{isa = XCConfigurationList; buildConfigurations = ({DC}, {RC}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
        {CLT} = {{isa = XCConfigurationList; buildConfigurations = ({AD}, {AR}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
        {LPR} = {{
            isa = XCLocalSwiftPackageReference;
            relativePath = ../..;
        }};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
        {PDC} = {{isa = XCSwiftPackageProductDependency; package = {LPR}; productName = AgentClientCore; }};
        {PDI} = {{isa = XCSwiftPackageProductDependency; package = {LPR}; productName = AgentClientIO; }};
        {PDS} = {{isa = XCSwiftPackageProductDependency; package = {LPR}; productName = AgentClientiOS; }};
/* End XCSwiftPackageProductDependency section */
    }};
    rootObject = {P};
}}
""")
print(f"Wrote {pbxproj}")

# AppEntry.swift
entry = os.path.join(SRC, "AppEntry.swift")
with open(entry, "w") as f:
    f.write("""import AgentClientiOS
import SwiftUI

@main
struct MacRelayiOSAppEntry: App {
    @StateObject private var viewModel = RelayClientViewModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                PairingView(viewModel: viewModel)
                    .tabItem { Label("Pair", systemImage: "link") }
                ConnectionStatusView(viewModel: viewModel)
                    .tabItem { Label("Net", systemImage: "antenna.radiowaves.left.and.right") }
                SessionSnapshotView(viewModel: viewModel)
                    .tabItem { Label("Sess", systemImage: "rectangle.3.group") }
                EventReplayListView(viewModel: viewModel)
                    .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            }
            .onOpenURL { url in
                Task {
                    try? await viewModel.claimFromURL(url)
                }
            }
        }
    }
}
""")
print(f"Wrote {entry}")

# Info.plist
plist = os.path.join(SRC, "Info.plist")
with open(plist, "w") as f:
    f.write("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key><string>MacRelay</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>NSCameraUsageDescription</key><string>Scan the MacRelay pairing QR code from your Mac.</string>
    <key>UIRequiresFullScreen</key><true/>
    <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
    <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
    <key>CFBundleURLTypes</key><array><dict>
        <key>CFBundleURLName</key><string>com.xiangyingchang.macrelay</string>
        <key>CFBundleURLSchemes</key><array><string>macrelay</string></array>
    </dict></array>
</dict>
</plist>
""")
print(f"Wrote {plist}")
print("\\n✅ Xcode project with package deps generated.")
print("   open Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj")
