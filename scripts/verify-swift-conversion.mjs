import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '..');
const swiftDir = path.join(repoRoot, 'TireShop');

let failed = false;
function check(name, ok, detail = '') {
  const mark = ok ? 'ok' : 'fail';
  console.log(`${mark} ${name}${detail ? ` - ${detail}` : ''}`);
  if (!ok) failed = true;
}

const swiftFiles = fs.readdirSync(swiftDir).filter((file) => file.endsWith('.swift')).sort();
check('swift files exist', swiftFiles.length > 0, `${swiftFiles.length} files`);

for (const file of swiftFiles) {
  const text = fs.readFileSync(path.join(swiftDir, file), 'utf8');
  let balance = 0;
  let min = 0;
  for (const char of text) {
    if (char === '{') balance += 1;
    if (char === '}') balance -= 1;
    min = Math.min(min, balance);
  }
  check(`balanced braces ${file}`, balance === 0 && min === 0);
}

const rootViews = fs.readFileSync(path.join(swiftDir, 'RootViews.swift'), 'utf8');

const allSwift = swiftFiles.map((file) => fs.readFileSync(path.join(swiftDir, file), 'utf8')).join('\n');
check('no forced casts', !allSwift.includes('as!'));
check('no duplicate private String helper', (allSwift.match(/private extension String/g) || []).length <= 1);

// Every destination flagged isBuilt: true must have a concrete case in DestinationView
// (across any Swift file containing the `switch destination.key` block).
const destinationsSwift = fs.readFileSync(path.join(swiftDir, 'Destinations.swift'), 'utf8');
const builtDestinationKeys = destinationsSwift
  .split('\n')
  .map((line) => line.match(/Destination\(key: "([^"]+)".*isBuilt: true/)?.[1])
  .filter(Boolean);
const destinationSwitchBlock = allSwift.match(/switch destination\.key \{([\s\S]*?)\n\s*default:/)?.[1] ?? '';
const renderedDestinationKeys = [...destinationSwitchBlock.matchAll(/case "([^"]+)":/g)].map((match) => match[1]);
const missingBuiltDestinations = builtDestinationKeys.filter((key) => !renderedDestinationKeys.includes(key));
check('built destinations render native screens', missingBuiltDestinations.length === 0, missingBuiltDestinations.join(', ') || `${builtDestinationKeys.length} built destinations`);

// Generated Xcode project must reference every Swift file, or the user's build won't include it.
const generatedPbxprojPath = path.join(repoRoot, 'TireShop.xcodeproj/project.pbxproj');
check('generated xcode project exists', fs.existsSync(generatedPbxprojPath));
if (fs.existsSync(generatedPbxprojPath)) {
  const generatedProject = fs.readFileSync(generatedPbxprojPath, 'utf8');
  const missingProjectFiles = swiftFiles.filter((file) => !generatedProject.includes(`/* ${file} */`));
  check('generated xcode project includes swift files', missingProjectFiles.length === 0, missingProjectFiles.join(', ') || `${swiftFiles.length} files`);
}
const generatedSchemePath = path.join(repoRoot, 'TireShop.xcodeproj/xcshareddata/xcschemes/TireShop.xcscheme');
check('generated shared xcode scheme exists', fs.existsSync(generatedSchemePath));
if (fs.existsSync(generatedSchemePath)) {
  const generatedScheme = fs.readFileSync(generatedSchemePath, 'utf8');
  check('generated scheme points at TireShop target', generatedScheme.includes('BlueprintName = "TireShop"') && generatedScheme.includes('BuildableName = "TireShop.app"'));
}

check('xcodegen project spec exists', fs.existsSync(path.join(repoRoot, 'project.yml')));
check('xcode project generator exists', fs.existsSync(path.join(repoRoot, 'scripts/generate-xcodeproj.mjs')));

if (failed) {
  process.exit(1);
}
