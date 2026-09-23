import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..');
const sourcePath = path.join(repoRoot, 'localization/messages.json');
const outputPath = path.join(repoRoot, 'TireShop/I18nMessages.swift');

function swiftString(value) {
  return `"${value
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n')
    .replaceAll('\t', '\\t')
    .replace(/[\u0000-\u001f\u007f]/g, character => `\\u{${character.charCodeAt(0).toString(16)}}`)}"`;
}

export function renderMessages(messages) {
  if (!messages || typeof messages !== 'object' || Array.isArray(messages)
      || Object.keys(messages).sort().join(',') !== 'en,zh') {
    throw new Error('Translations must contain exactly the en and zh dictionaries.');
  }
  const dictionaries = ['en', 'zh'].map(language => {
    const entries = messages[language];
    if (!entries || typeof entries !== 'object' || Array.isArray(entries)) {
      throw new Error(`Invalid ${language} translation dictionary.`);
    }
    const lines = [`        .${language}: [`];
    for (const key of Object.keys(entries).sort()) {
      if (typeof entries[key] !== 'string') {
        throw new Error(`Translation ${language}.${key} must be a string.`);
      }
      lines.push(`            ${swiftString(key)}: ${swiftString(entries[key])},`);
    }
    if (Object.keys(entries).length === 0) {
      return `        .${language}: [:]`;
    }
    lines.push('        ]');
    return lines.join('\n');
  });
  return `import Foundation

// Generated from localization/messages.json by scripts/generate-i18n-swift.mjs.
extension I18nStore {
    static let messages: [AppLanguage: [String: String]] = [
${dictionaries.join(',\n')}
    ]
}
`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  const args = process.argv.slice(2);
  if (args.some(arg => arg !== '--check')) {
    throw new Error('Usage: node scripts/generate-i18n-swift.mjs [--check]');
  }
  const output = renderMessages(JSON.parse(fs.readFileSync(sourcePath, 'utf8')));
  if (args.includes('--check')) {
    if (!fs.existsSync(outputPath) || fs.readFileSync(outputPath, 'utf8') !== output) {
      throw new Error('I18nMessages.swift is out of date. Run node scripts/generate-i18n-swift.mjs.');
    }
  } else {
    fs.writeFileSync(outputPath, output);
  }
}
