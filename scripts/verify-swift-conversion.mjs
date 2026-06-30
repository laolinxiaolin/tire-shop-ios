import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const swiftDir = path.join(repoRoot, 'SwiftApp/TireShop');

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

const sourceI18n = fs.readFileSync(path.join(repoRoot, 'src/lib/i18n.tsx'), 'utf8');
const swiftI18n = fs.readFileSync(path.join(swiftDir, 'I18nMessages.swift'), 'utf8');
const sourceEntries = (sourceI18n.match(/'[^']+'\s*:/g) || []).length;
const swiftEntries = (swiftI18n.match(/^            "/gm) || []).length;
check('i18n entry parity', sourceEntries === swiftEntries, `${sourceEntries} source / ${swiftEntries} swift`);

const rootViews = fs.readFileSync(path.join(swiftDir, 'RootViews.swift'), 'utf8');
const placeholderCalls = (rootViews.match(/PlaceholderScreen\(/g) || []).length;
check('placeholder fallbacks only', placeholderCalls === 2, `${placeholderCalls} calls`);

const allSwift = swiftFiles.map((file) => fs.readFileSync(path.join(swiftDir, file), 'utf8')).join('\n');
check('no forced casts', !allSwift.includes('as!'));
check('no duplicate private String helper', !allSwift.includes('private extension String'));

const typeSource = fs.readFileSync(path.join(repoRoot, 'src/navigation/types.ts'), 'utf8');
const routeBlock = typeSource.match(/export type RootStackParamList = \{([\s\S]*?)\n\};/)?.[1] ?? '';
const sourceRoutes = [...routeBlock.matchAll(/^  ([A-Z][A-Za-z0-9]*):/gm)].map((match) => match[1]);
const appRouteBlock = rootViews.match(/enum AppRoute: Hashable \{([\s\S]*?)\n\}/)?.[1] ?? '';
const swiftRoutes = [...appRouteBlock.matchAll(/^\s*case\s+([A-Za-z][A-Za-z0-9]*)/gm)].map((match) => match[1]);
const routeMap = {
  Main: 'tab shell',
  Module: 'module',
  CustomizeTabs: 'customizeTabs',
  SkuDetail: 'skuDetail',
  SkuForm: 'skuForm',
  AdjustStock: 'adjustStock',
  SaleDetail: 'saleDetail',
  EditSale: 'editSale',
  StartReturn: 'startReturn',
  WorkOrderDetail: 'workOrderDetail',
  InventoryCountDetail: 'inventoryCountDetail',
  NewInventoryCount: 'newInventoryCount',
  ContainerDetail: 'containerDetail',
  TapToPay: 'tapToPay',
  CustomerDetail: 'customerDetail',
  Profile: 'profile',
  SkuPicker: 'skuPicker',
  CustomerPicker: 'customerPicker',
  NewCustomer: 'newCustomer'
};
const missingRoutes = sourceRoutes.filter((route) => routeMap[route] !== 'tab shell' && !swiftRoutes.includes(routeMap[route]));
check('root stack routes converted', missingRoutes.length === 0, missingRoutes.join(', ') || `${sourceRoutes.length} source routes`);

const apiSource = fs.readFileSync(path.join(repoRoot, 'src/lib/api.ts'), 'utf8');
const endpointGroups = [...apiSource.matchAll(/^export const (\w+) = \{/gm)].map((match) => match[1]);
const serviceMap = {
  auth: ['AuthStore', 'APIClient'],
  dashboard: ['DashboardAPI'],
  tireAttributes: ['TireAttributesAPI'],
  inventory: ['InventoryAPI'],
  sales: ['SalesAPI'],
  customers: ['CustomersAPI'],
  services: ['ServicesAPI'],
  workOrders: ['WorkOrdersAPI'],
  returns: ['ReturnsAPI'],
  suppliers: ['SuppliersAPI'],
  receivables: ['MoneyAPI'],
  payables: ['MoneyAPI'],
  inventoryCounts: ['InventoryCountsAPI'],
  containers: ['ContainersAPI'],
  accounting: ['AccountingAPI'],
  cashAccounts: ['CashAccountsAPI'],
  fet: ['FetAPI'],
  eod: ['EodAPI'],
  activity: ['ActivityAPI'],
  approvals: ['ApprovalsAPI'],
  users: ['UsersAPI'],
  roles: ['RolesAPI'],
  apiKeys: ['ApiKeysAPI'],
  settings: ['SettingsAPI'],
  invoices: ['InvoicesAPI'],
  payments: ['PaymentsAPI']
};
const missingServiceGroups = endpointGroups.filter((group) => !(serviceMap[group] ?? []).some((name) => allSwift.includes(name)));
check('api endpoint groups converted', missingServiceGroups.length === 0, missingServiceGroups.join(', ') || `${endpointGroups.length} groups`);

const destinationsSwift = fs.readFileSync(path.join(swiftDir, 'Destinations.swift'), 'utf8');
const builtDestinationKeys = destinationsSwift
  .split('\n')
  .map((line) => {
    const match = line.match(/Destination\(key: "([^"]+)".*isBuilt: true/);
    return match?.[1];
  })
  .filter(Boolean);
const destinationSwitchBlock = rootViews.match(/struct DestinationView[\s\S]*?switch destination\.key \{([\s\S]*?)\n\s*default:/)?.[1] ?? '';
const renderedDestinationKeys = [...destinationSwitchBlock.matchAll(/case "([^"]+)":/g)].map((match) => match[1]);
const missingBuiltDestinations = builtDestinationKeys.filter((key) => !renderedDestinationKeys.includes(key));
check('built destinations render native screens', missingBuiltDestinations.length === 0, missingBuiltDestinations.join(', ') || `${builtDestinationKeys.length} built destinations`);

check('xcodegen project spec exists', fs.existsSync(path.join(repoRoot, 'SwiftApp/project.yml')));
const generatedPbxprojPath = path.join(repoRoot, 'SwiftApp/TireShop.xcodeproj/project.pbxproj');
check('generated xcode project exists', fs.existsSync(generatedPbxprojPath));
if (fs.existsSync(generatedPbxprojPath)) {
  const generatedProject = fs.readFileSync(generatedPbxprojPath, 'utf8');
  const missingProjectFiles = swiftFiles.filter((file) => !generatedProject.includes(`/* ${file} */`));
  check('generated xcode project includes swift files', missingProjectFiles.length === 0, missingProjectFiles.join(', ') || `${swiftFiles.length} files`);
  check('generated xcode project has no missing appicon reference', !generatedProject.includes('ASSETCATALOG_COMPILER_APPICON_NAME'));
}
const generatedSchemePath = path.join(repoRoot, 'SwiftApp/TireShop.xcodeproj/xcshareddata/xcschemes/TireShop.xcscheme');
check('generated shared xcode scheme exists', fs.existsSync(generatedSchemePath));
if (fs.existsSync(generatedSchemePath)) {
  const generatedScheme = fs.readFileSync(generatedSchemePath, 'utf8');
  check('generated scheme points at TireShop target', generatedScheme.includes('BlueprintName = "TireShop"') && generatedScheme.includes('BuildableName = "TireShop.app"'));
}
check('i18n generator exists', fs.existsSync(path.join(repoRoot, 'SwiftApp/scripts/generate-i18n-swift.mjs')));
check('xcode project generator exists', fs.existsSync(path.join(repoRoot, 'SwiftApp/scripts/generate-xcodeproj.mjs')));

const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
check('package swift:i18n script exists', packageJson.scripts?.['swift:i18n'] === 'node SwiftApp/scripts/generate-i18n-swift.mjs');
check('package swift:xcodeproj script exists', packageJson.scripts?.['swift:xcodeproj'] === 'node SwiftApp/scripts/generate-xcodeproj.mjs');
check('package swift:verify script exists', packageJson.scripts?.['swift:verify'] === 'node SwiftApp/scripts/verify-swift-conversion.mjs');

if (failed) {
  process.exit(1);
}
