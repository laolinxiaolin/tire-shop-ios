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

const catalog = {
  sourceLanguage: 'en',
  strings,
  version: '1.0'
};

fs.writeFileSync(outputPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(`Generated ${path.relative(repoRoot, outputPath)} with ${Object.keys(strings).length} strings.`);
