import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { backupFileName, decodeXml, readLocalFile, xmlFileName } from '../dist/smartform-file.js';

const XML = Buffer.from('<?xml version="1.0"?>\n<sf:SMARTFORM xmlns:sf="urn:sap-com:SmartForms:2000:internal-structure"/>');

test('xmlFileName is upper case and without slashes', () => {
  assert.equal(xmlFileName(' zai_sf_delnote '), 'ZAI_SF_DELNOTE.xml');
  assert.equal(xmlFileName('/ABC/FORM'), '#ABC#FORM.xml');
});

test('backupFileName with UTC date and time', () => {
  const now = new Date(Date.UTC(2026, 8, 26, 14, 5, 9));
  assert.equal(backupFileName('zai_sf_delnote', now), 'ZAI_SF_DELNOTE_20260926_140509.xml');
});

test('decodeXml accepts SmartForms XML only', () => {
  assert.deepEqual(decodeXml(XML.toString('base64')), XML);
  assert.throws(() => decodeXml(''), /is not a SmartForms/);
  assert.throws(() => decodeXml(Buffer.from('<a/>').toString('base64')), /is not a SmartForms/);
});

test('readLocalFile reads the file or gives a clear error', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'sf-'));
  const path = join(dir, 'x.xml');
  await writeFile(path, XML);
  assert.deepEqual(await readLocalFile(path), XML);
  await assert.rejects(() => readLocalFile(join(dir, 'missing.xml')), /File not found/);
});
