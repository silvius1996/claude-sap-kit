import { readFile } from 'node:fs/promises';

// SmartForms XML returned by the FM as xstring (base64 via SOAP-RFC)
export function decodeXml(base64: string): Buffer {
  const data = Buffer.from(base64.replace(/\s+/g, ''), 'base64');
  const head = data.subarray(0, 2000).toString('utf8');
  if (!/<[\w-]+:SMARTFORM[\s>/]/.test(head)) {
    throw new Error('The returned content is not a SmartForms XML');
  }
  return data;
}

// Namespaced names (/XYZ/...) are not valid file names
function safeName(name: string): string {
  return name.trim().toUpperCase().replace(/\//g, '#');
}

export function xmlFileName(name: string): string {
  return `${safeName(name)}.xml`;
}

export function backupFileName(name: string, now: Date = new Date()): string {
  const stamp = now.toISOString().slice(0, 19).replace(/-|:/g, '').replace('T', '_');
  return `${safeName(name)}_${stamp}.xml`;
}

export async function readLocalFile(path: string): Promise<Buffer> {
  try {
    return await readFile(path);
  } catch {
    throw new Error(`File not found: ${path}`);
  }
}
