import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { renderMessages } from './generate-i18n-swift.mjs';

test('checked-in translations regenerate exactly from any working directory', () => {
  const messages = JSON.parse(fs.readFileSync(new URL('../localization/messages.json', import.meta.url), 'utf8'));
  const generated = fs.readFileSync(new URL('../TireShop/I18nMessages.swift', import.meta.url), 'utf8');
  assert.equal(renderMessages(messages), generated);
  const result = spawnSync(process.execPath,
    [fileURLToPath(new URL('./generate-i18n-swift.mjs', import.meta.url)), '--check'],
    { cwd: os.tmpdir(), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

test('Swift literals preserve quotes, backslashes, newlines, tabs and control characters', () => {
  const rendered = renderMessages({ en: { 'a"b': '"\\(literal)\n\r\t\u0000' }, zh: { text: '轮胎' } });
  assert.ok(rendered.includes('"a\\"b": "\\"\\\\(literal)\\n\\r\\t\\u{0}"'));
  assert.ok(rendered.includes('"text": "轮胎"'));
  assert.ok(renderMessages({ en: {}, zh: {} }).includes('.en: [:]'));
});

test('invalid translation sources fail instead of coercing or dropping content', () => {
  for (const messages of [null, [], { en: {} }, { en: {}, zh: {}, fr: {} },
    { en: [], zh: {} }, { en: { invalid: 12 }, zh: {} }]) {
    assert.throws(() => renderMessages(messages));
  }
});
