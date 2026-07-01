import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '..');
const appRoot = repoRoot;
const sourceDir = path.join(appRoot, 'TireShop');
const projectDir = path.join(appRoot, 'TireShop.xcodeproj');
const pbxprojPath = path.join(projectDir, 'project.pbxproj');
const schemeDir = path.join(projectDir, 'xcshareddata/xcschemes');
const schemePath = path.join(schemeDir, 'TireShop.xcscheme');

const swiftFiles = fs
  .readdirSync(sourceDir)
  .filter((file) => file.endsWith('.swift'))
  .sort();

function id(label) {
  return crypto.createHash('sha1').update(label).digest('hex').slice(0, 24).toUpperCase();
}

function q(value) {
  return `"${String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

const ids = {
  project: id('project'),
  mainGroup: id('mainGroup'),
  sourceGroup: id('sourceGroup'),
  productGroup: id('productGroup'),
  nativeTarget: id('nativeTarget'),
  product: id('product'),
  sourcesPhase: id('sourcesPhase'),
  frameworksPhase: id('frameworksPhase'),
  resourcesPhase: id('resourcesPhase'),
  projectConfigList: id('projectConfigList'),
  targetConfigList: id('targetConfigList'),
  projectDebug: id('projectDebug'),
  projectRelease: id('projectRelease'),
  targetDebug: id('targetDebug'),
  targetRelease: id('targetRelease'),
  assetsFile: id('file:Assets.xcassets'),
  assetsBuild: id('build:Assets.xcassets'),
  entitlementsFile: id('file:TireShop.entitlements'),
  stripePackage: id('stripePackage'),
  stripeProduct: id('stripeProduct'),
  stripeBuild: id('stripeBuild'),
  stripePaymentSheetPackage: id('stripePaymentSheetPackage'),
  stripePaymentSheetProduct: id('stripePaymentSheetProduct'),
  stripePaymentSheetBuild: id('stripePaymentSheetBuild')
};

const fileIds = new Map(swiftFiles.map((file) => [file, id(`file:${file}`)]));
const buildIds = new Map(swiftFiles.map((file) => [file, id(`build:${file}`)]));

const fileRefs = swiftFiles
  .map((file) => `		${fileIds.get(file)} /* ${file} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${q(file)}; sourceTree = "<group>"; };`)
  .join('\n');

const buildFiles = swiftFiles
  .map((file) => `		${buildIds.get(file)} /* ${file} in Sources */ = {isa = PBXBuildFile; fileRef = ${fileIds.get(file)} /* ${file} */; };`)
  .join('\n');

const sourceChildren = swiftFiles
  .map((file) => `				${fileIds.get(file)} /* ${file} */,`)
  .join('\n');

const sourceBuildFiles = swiftFiles
  .map((file) => `				${buildIds.get(file)} /* ${file} in Sources */,`)
  .join('\n');

const commonProjectSettings = `
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.10;`;

const commonTargetSettings = `
				CODE_SIGN_STYLE = Automatic;
				CODE_SIGN_ENTITLEMENTS = TireShop/TireShop.entitlements;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = C8S3S8T2K2;
				DEVELOPMENT_ASSET_PATHS = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				INFOPLIST_KEY_CFBundleDisplayName = "Tire Force US";
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.business";
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Tire Force uses your location while accepting in-person card payments so Stripe Terminal can connect this device to the store.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.tireforce.salesystemi;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.10;
				TARGETED_DEVICE_FAMILY = "1,2";`;

const pbxproj = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
${buildFiles}
		${ids.stripeBuild} /* StripeTerminal in Frameworks */ = {isa = PBXBuildFile; productRef = ${ids.stripeProduct} /* StripeTerminal */; };
		${ids.stripePaymentSheetBuild} /* StripePaymentSheet in Frameworks */ = {isa = PBXBuildFile; productRef = ${ids.stripePaymentSheetProduct} /* StripePaymentSheet */; };
		${ids.assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.assetsFile} /* Assets.xcassets */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
${fileRefs}
		${ids.product} /* TireShop.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TireShop.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.assetsFile} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${ids.entitlementsFile} /* TireShop.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = TireShop.entitlements; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${ids.frameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.stripeBuild} /* StripeTerminal in Frameworks */,
				${ids.stripePaymentSheetBuild} /* StripePaymentSheet in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${ids.mainGroup} = {
			isa = PBXGroup;
			children = (
				${ids.sourceGroup} /* TireShop */,
				${ids.productGroup} /* Products */,
			);
			sourceTree = "<group>";
		};
		${ids.sourceGroup} /* TireShop */ = {
			isa = PBXGroup;
			children = (
${sourceChildren}
				${ids.assetsFile} /* Assets.xcassets */,
				${ids.entitlementsFile} /* TireShop.entitlements */,
			);
			path = TireShop;
			sourceTree = "<group>";
		};
		${ids.productGroup} /* Products */ = {
			isa = PBXGroup;
			children = (
				${ids.product} /* TireShop.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${ids.nativeTarget} /* TireShop */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${ids.targetConfigList} /* Build configuration list for PBXNativeTarget "TireShop" */;
			buildPhases = (
				${ids.sourcesPhase} /* Sources */,
				${ids.frameworksPhase} /* Frameworks */,
				${ids.resourcesPhase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TireShop;
			productName = TireShop;
			packageProductDependencies = (
				${ids.stripeProduct} /* StripeTerminal */,
				${ids.stripePaymentSheetProduct} /* StripePaymentSheet */,
			);
			productReference = ${ids.product} /* TireShop.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${ids.project} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = YES;
				LastSwiftUpdateCheck = 1540;
				LastUpgradeCheck = 1540;
				TargetAttributes = {
					${ids.nativeTarget} = {
						CreatedOnToolsVersion = 15.4;
					};
				};
			};
			buildConfigurationList = ${ids.projectConfigList} /* Build configuration list for PBXProject "TireShop" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = ${ids.mainGroup};
			packageReferences = (
				${ids.stripePackage} /* XCRemoteSwiftPackageReference "stripe-terminal-ios" */,
				${ids.stripePaymentSheetPackage} /* XCRemoteSwiftPackageReference "stripe-ios-spm" */,
			);
			productRefGroup = ${ids.productGroup} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				${ids.nativeTarget} /* TireShop */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${ids.resourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.assetsBuild} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${ids.sourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${sourceBuildFiles}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		${ids.projectDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${commonProjectSettings}
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
			};
			name = Debug;
		};
		${ids.projectRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${commonProjectSettings}
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		${ids.targetDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${commonTargetSettings}
			};
			name = Debug;
		};
		${ids.targetRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
${commonTargetSettings}
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${ids.projectConfigList} /* Build configuration list for PBXProject "TireShop" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.projectDebug} /* Debug */,
				${ids.projectRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${ids.targetConfigList} /* Build configuration list for PBXNativeTarget "TireShop" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.targetDebug} /* Debug */,
				${ids.targetRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
		${ids.stripePackage} /* XCRemoteSwiftPackageReference "stripe-terminal-ios" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/stripe/stripe-terminal-ios";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 5.6.0;
			};
		};
		${ids.stripePaymentSheetPackage} /* XCRemoteSwiftPackageReference "stripe-ios-spm" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/stripe/stripe-ios-spm";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 26.1.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		${ids.stripeProduct} /* StripeTerminal */ = {
			isa = XCSwiftPackageProductDependency;
			package = ${ids.stripePackage} /* XCRemoteSwiftPackageReference "stripe-terminal-ios" */;
			productName = StripeTerminal;
		};
		${ids.stripePaymentSheetProduct} /* StripePaymentSheet */ = {
			isa = XCSwiftPackageProductDependency;
			package = ${ids.stripePaymentSheetPackage} /* XCRemoteSwiftPackageReference "stripe-ios-spm" */;
			productName = StripePaymentSheet;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = ${ids.project} /* Project object */;
}
`;

fs.mkdirSync(projectDir, { recursive: true });
fs.writeFileSync(pbxprojPath, pbxproj);

const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "${ids.nativeTarget}"
               BuildableName = "TireShop.app"
               BlueprintName = "TireShop"
               ReferencedContainer = "container:TireShop.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${ids.nativeTarget}"
            BuildableName = "TireShop.app"
            BlueprintName = "TireShop"
            ReferencedContainer = "container:TireShop.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${ids.nativeTarget}"
            BuildableName = "TireShop.app"
            BlueprintName = "TireShop"
            ReferencedContainer = "container:TireShop.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
`;

fs.mkdirSync(schemeDir, { recursive: true });
fs.writeFileSync(schemePath, scheme);
console.log(`Generated ${path.relative(repoRoot, pbxprojPath)} with ${swiftFiles.length} Swift files.`);
console.log(`Generated ${path.relative(repoRoot, schemePath)}.`);
