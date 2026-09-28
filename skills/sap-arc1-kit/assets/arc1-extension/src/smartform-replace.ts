// Reads the ZAI_SMARTFORM_REPLACE response (mode P) and builds the summary shown before confirmation.
import { decodeXml } from './smartform-file.js';
import { readElement } from './soap-rfc.js';

export interface PrepareResult {
  devclass: string;
  author: string;
  lastUser: string;
  lastDate: string;
  lastTime: string;
  trOwner: string;
  token: string;
  xml: Buffer;
}

export function readPrepareResponse(body: string): PrepareResult {
  const token = readElement(body, 'EV_TOKEN').trim();
  if (!token) throw new Error('Prepare response without token');
  return {
    devclass: readElement(body, 'EV_DEVCLASS').trim(),
    author: readElement(body, 'EV_AUTHOR').trim(),
    lastUser: readElement(body, 'EV_LASTUSER').trim(),
    lastDate: readElement(body, 'EV_LASTDATE').trim(),
    lastTime: readElement(body, 'EV_LASTTIME').trim(),
    trOwner: readElement(body, 'EV_TR_OWNER').trim(),
    token,
    xml: decodeXml(readElement(body, 'EV_XML')),
  };
}

// SOAP-RFC returns DATS/TIMS as 2026-09-27 / 18:07:57; the internal format is accepted too
export function formatSapDateTime(date: string, time: string): string {
  const d = date.replace(/\D/g, '');
  const t = time.replace(/\D/g, '');
  if (d.length !== 8) return '-';
  return `${d.slice(6, 8)}.${d.slice(4, 6)}.${d.slice(0, 4)} ${t.slice(0, 2)}:${t.slice(2, 4)}`;
}

export function formatPrepareSummary(p: {
  original: string;
  copy: string;
  transport: string;
  backup: string;
  result: PrepareResult;
}): string {
  const r = p.result;
  return [
    `Replacement ready: ${p.original} ← ${p.copy}`,
    `Package: ${r.devclass} · Author: ${r.author}`,
    `Original last changed by ${r.lastUser} on ${formatSapDateTime(r.lastDate, r.lastTime)}`,
    // The owner helps to spot a wrong request (e.g. a colleague's one)
    `Transport request: ${p.transport} (owner ${r.trOwner || '-'})`,
    `Backup of the original: ${p.backup}`,
    `Token: ${r.token}`,
    'Nothing changed in SAP. To proceed: action=execute with the same token, after explicit confirmation by the user.',
  ].join('\n');
}
