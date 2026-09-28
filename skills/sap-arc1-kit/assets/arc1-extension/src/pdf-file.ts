import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

// PDF returned by the FM as xstring, which SOAP-RFC transports as base64
export function decodePdf(base64: string): Buffer {
  const data = Buffer.from(base64.replace(/\s+/g, ''), 'base64');
  if (data.length < 5 || data.subarray(0, 5).toString('latin1') !== '%PDF-') {
    throw new Error('The returned content is not a PDF');
  }
  return data;
}

export function pdfFileName(document: string, outputType: string, now: Date = new Date()): string {
  const doc = document.trim().replace(/^0+/, '') || '0';
  const stamp = now.toISOString().slice(0, 19).replace(/-|:/g, '').replace('T', '_');
  return `${doc}_${outputType.trim().toUpperCase()}_${stamp}.pdf`;
}

export async function savePdf(dir: string, name: string, data: Buffer): Promise<string> {
  await mkdir(dir, { recursive: true });
  const path = join(dir, name);
  await writeFile(path, data);
  return path;
}
