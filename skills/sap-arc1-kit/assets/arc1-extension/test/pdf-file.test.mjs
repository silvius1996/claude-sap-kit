import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { decodePdf, pdfFileName, savePdf } from '../dist/pdf-file.js';

const PDF = Buffer.from('%PDF-1.7\ntest\n%%EOF');

test('decodePdf accepts base64 split over several lines', () => {
  const b64 = PDF.toString('base64').replace(/(.{8})/g, '$1\n');
  assert.deepEqual(decodePdf(b64), PDF);
});

test('decodePdf rejects non-PDF content', () => {
  assert.throws(() => decodePdf(''), /is not a PDF/);
  assert.throws(() => decodePdf(Buffer.from('hello').toString('base64')), /is not a PDF/);
});

test('pdfFileName strips leading zeros and uses UTC time', () => {
  const now = new Date(Date.UTC(2026, 8, 26, 14, 5, 9));
  assert.equal(pdfFileName('0000012345', 'ba00', now), '12345_BA00_20260926_140509.pdf');
});

test('savePdf creates the folder and writes the file', async () => {
  const base = await mkdtemp(join(tmpdir(), 'preview-'));
  const path = await savePdf(join(base, 'a', 'b'), 'x.pdf', PDF);
  assert.equal(path, join(base, 'a', 'b', 'x.pdf'));
  assert.deepEqual(await readFile(path), PDF);
});
