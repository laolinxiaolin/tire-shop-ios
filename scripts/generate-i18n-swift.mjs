import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const sourcePath = path.join(repoRoot, 'src/lib/i18n.tsx');
const outputPath = path.join(repoRoot, 'SwiftApp/TireShop/I18nMessages.swift');

const source = fs.readFileSync(sourcePath, 'utf8');

function extractObject(name, endMarker, closeLength) {
  const start = source.indexOf(`const ${name}`);
  if (start < 0) throw new Error(`Could not find ${name}`);
  const bodyStart = source.indexOf('{', start);
  const end = source.indexOf(endMarker, bodyStart);
  if (end < 0) throw new Error(`Could not find end for ${name}`);
  const literal = source.slice(bodyStart, end + closeLength).trim().replace(/;$/, '');
  return vm.runInNewContext(`(${literal})`, {});
}

function swiftString(value) {
  return `"${String(value)
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n')}"`
}

function renderDictionary(language, messages) {
  const lines = [`        .${language}: [`];
  for (const key of Object.keys(messages).sort()) {
    lines.push(`            ${swiftString(key)}: ${swiftString(messages[key])},`);
  }
  lines.push('        ]');
  return lines.join('\n');
}

const en = extractObject('en', '} satisfies Dict;', 1);
const zh = extractObject('zh', '\n};\n\nconst messages:', 2);

const output = `import Foundation

extension I18nStore {
    static let messages: [AppLanguage: [String: String]] = [
${renderDictionary('en', en)},
${renderDictionary('zh', zh)}
    ]
}
`;

fs.writeFileSync(outputPath, output);
