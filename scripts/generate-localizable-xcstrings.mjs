import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '..');
const messagesPath = path.join(repoRoot, 'TireShop/I18nMessages.swift');
const outputPath = path.join(repoRoot, 'TireShop/Localizable.xcstrings');
const source = fs.readFileSync(messagesPath, 'utf8');

function parseLanguage(language, nextMarker) {
  const marker = `        .${language}: [`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Could not find ${language} messages`);

  const bodyStart = start + marker.length;
  const end = source.indexOf(nextMarker, bodyStart);
  if (end < 0) throw new Error(`Could not find the end of ${language} messages`);

  const messages = new Map();
  const body = source.slice(bodyStart, end);
  const linePattern = /^            "((?:[^"\\]|\\.)+)": "((?:[^"\\]|\\.)*)",$/gm;

  for (const match of body.matchAll(linePattern)) {
    const key = JSON.parse(`"${match[1]}"`);
    const value = JSON.parse(`"${match[2]}"`);
    messages.set(key, value);
  }

  return messages;
}

const english = parseLanguage('en', '\n        ],\n        .zh: [');
const chinese = parseLanguage('zh', '\n        ]\n    ]');
const translationsByEnglishValue = new Map();

for (const [key, englishValue] of english) {
  const chineseValue = chinese.get(key);
  if (!chineseValue || englishValue.includes('{')) continue;

  const candidates = translationsByEnglishValue.get(englishValue) ?? new Map();
  candidates.set(chineseValue, (candidates.get(chineseValue) ?? 0) + 1);
  translationsByEnglishValue.set(englishValue, candidates);
}

const literalAliases = new Map([
  ['Confirming...', chinese.get('newQuote.confirming')],
  ['Deleting...', chinese.get('common.deleting')],
  ['Loading...', chinese.get('common.loading')],
  ['Processing...', chinese.get('tapToPay.processing')]
]);
for (const [englishValue, chineseValue] of literalAliases) {
  translationsByEnglishValue.set(englishValue, new Map([[chineseValue, 1]]));
}

const strings = {};
for (const englishValue of [...translationsByEnglishValue.keys()].sort()) {
  const candidates = translationsByEnglishValue.get(englishValue);
  const chineseValue = [...candidates.entries()]
    .sort((left, right) => right[1] - left[1])[0][0];

  strings[englishValue] = {
    localizations: {
      'zh-Hans': {
        stringUnit: {
          state: 'translated',
          value: chineseValue
        }
      }
    }
  };
}

// Xcode also extracts SwiftUI literals and translators can edit this catalog
// directly. Preserve those entries and translations when syncing dictionary copy.
const catalog = fs.existsSync(outputPath)
  ? JSON.parse(fs.readFileSync(outputPath, 'utf8'))
  : { sourceLanguage: 'en', strings: {}, version: '1.0' };
for (const [key, entry] of Object.entries(strings)) {
  const existing = catalog.strings[key];
  catalog.strings[key] = existing
    ? { ...entry, ...existing, localizations: { ...entry.localizations, ...existing.localizations } }
    : entry;
}
catalog.strings = Object.fromEntries(Object.entries(catalog.strings).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));

// Match Xcode's catalog formatting, including its sorted numeric-looking keys.
function formatCatalog(value, depth = 0) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return JSON.stringify(value);
  const indent = '  '.repeat(depth);
  const lines = Object.keys(value).sort().map((key) =>
    `${indent}  ${JSON.stringify(key)} : ${formatCatalog(value[key], depth + 1)}`
  );
  return `{\n${lines.join(',\n')}\n${indent}}`;
}

fs.writeFileSync(outputPath, `${formatCatalog(catalog)}\n`);
console.log(`Generated ${path.relative(repoRoot, outputPath)} with ${Object.keys(catalog.strings).length} strings.`);
