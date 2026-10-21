// Replacement of a customer Adobe form with an approved ZAI_* copy: reads the ZAI_ADOBE_FORM_REPLACE response
// (mode P), checks that the copy differs from the original only in the layout, builds the summary shown before
// confirmation.
import { decodeFormXml, decodeLayout } from './adobe-form-file.js';
import { readElement } from './soap-rfc.js';

export interface AdobePrepareResult {
  devclass: string;
  author: string;
  lastUser: string;
  trOwner: string;
  token: string;
  form: Buffer;
  layout: Buffer;
}

export function readAdobePrepareResponse(body: string): AdobePrepareResult {
  const token = readElement(body, 'EV_TOKEN').trim();
  if (!token) throw new Error('Prepare response without token');
  return {
    devclass: readElement(body, 'EV_DEVCLASS').trim(),
    author: readElement(body, 'EV_AUTHOR').trim(),
    lastUser: readElement(body, 'EV_LASTUSER').trim(),
    trOwner: readElement(body, 'EV_TR_OWNER').trim(),
    token,
    form: decodeFormXml(readElement(body, 'EV_FORM')),
    layout: decodeLayout(readElement(body, 'EV_LAYOUT')),
  };
}

// Administrative data: they differ between a copy and its original even when nothing else does
export const IGNORED_ELEMENTS = ['FIRSTUSER', 'FIRSTDATE', 'FIRSTTIME', 'LASTUSER', 'LASTDATE', 'LASTTIME', 'CACHE_INFO'];

const MAX_SHOWN = 5;

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

interface Line {
  number: number;
  text: string;
}

function comparableLines(xml: Buffer, rename?: { from: string; to: string }): Line[] {
  let text = xml.toString('utf8');
  if (rename) {
    // The copy name counts as the original name, wherever the form XML names the form itself
    const name = new RegExp(`(?<![A-Z0-9_/])${escapeRegExp(rename.from)}(?![A-Z0-9_/])`, 'g');
    text = text.replace(name, rename.to);
  }
  const ignored = new RegExp(
    `^\\s*<(?:[\\w-]+:)?(${IGNORED_ELEMENTS.join('|')})(?:\\s[^>]*)?(?:/>|>[^<]*</(?:[\\w-]+:)?\\1>)\\s*$`,
  );
  return text
    .split(/\r?\n/)
    .map((line, i) => ({ number: i + 1, text: line.trim() }))
    .filter((line) => line.text !== '' && !ignored.test(line.text));
}

// The replacement writes only the layout: context, interface and properties of the copy must be those of the
// original. Both XML come from ZAI_ADOBE_FORM_READ (one element per line, ids renumbered, CACHE_INFO empty).
// Returns the differing lines (empty when the copy is the same as the original outside the layout).
export function compareFormXml(original: Buffer, copy: Buffer, originalName: string, copyName: string): string[] {
  const a = comparableLines(original);
  const b = comparableLines(copy, { from: copyName.trim().toUpperCase(), to: originalName.trim().toUpperCase() });
  let start = 0;
  while (start < a.length && start < b.length && a[start].text === b[start].text) start++;
  let endA = a.length;
  let endB = b.length;
  while (endA > start && endB > start && a[endA - 1].text === b[endB - 1].text) {
    endA--;
    endB--;
  }
  if (start === endA && start === endB) return [];

  // Line numbers of the files, so that the differences can be found in them
  const shown = (lines: Line[], from: number, to: number, label: string) =>
    lines.slice(from, Math.min(to, from + MAX_SHOWN)).map((line) => `${label} line ${line.number}: ${line.text}`);
  return [
    `${endA - start} line(s) of the original and ${endB - start} of the copy differ`,
    ...shown(a, start, endA, 'original'),
    ...shown(b, start, endB, 'copy'),
  ];
}

export function formatAdobePrepareSummary(p: {
  original: string;
  copy: string;
  transport: string;
  backup: string[];
  result: AdobePrepareResult;
}): string {
  const r = p.result;
  return [
    `Replacement ready: layout of ${p.original} ← ${p.copy}`,
    `Package: ${r.devclass} · Author: ${r.author}`,
    `Original last changed by ${r.lastUser || '-'}`,
    // The owner helps to spot a wrong request (e.g. a colleague's one)
    `Transport request: ${p.transport} (owner ${r.trOwner || '-'})`,
    `Backup of the original: ${p.backup.join(', ')}`,
    'Checked: outside the layout the copy is the same as the original (context, interface, properties)',
    'Only the layout of the original language changes: translated layouts (SE63) stay as they are',
    `Token: ${r.token}`,
    'Nothing changed in SAP. To proceed: action=execute with the same token, after explicit confirmation by the user.',
  ].join('\n');
}
