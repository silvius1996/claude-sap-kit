// Adobe forms as local files: the form as XML without layout (<NAME>.form.xml), the layout as XDP
// (<NAME>.xdp) and the form interface as XML (<NAME>.interface.xml). SOAP-RFC transports them as base64.

const XDP_NAMESPACE = 'http://ns.adobe.com/xdp/';

export function checkFormXml(data: Buffer): Buffer {
  const head = data.subarray(0, 200).toString('utf8').replace(/^﻿/, '').trimStart();
  if (!head.startsWith('<')) {
    throw new Error('The form content is not an XML');
  }
  return data;
}

export function checkLayout(data: Buffer): Buffer {
  if (!data.toString('utf8').includes(XDP_NAMESPACE)) {
    throw new Error(`The layout is not an XDP (namespace ${XDP_NAMESPACE} missing)`);
  }
  return data;
}

function decode(base64: string): Buffer {
  return Buffer.from(base64.replace(/\s+/g, ''), 'base64');
}

export function decodeFormXml(base64: string): Buffer {
  return checkFormXml(decode(base64));
}

export function decodeLayout(base64: string): Buffer {
  return checkLayout(decode(base64));
}

// Name of the form interface, as stored in the form XML; undefined if it is not found
export function findInterfaceName(formXml: Buffer): string | undefined {
  const match = /<(?:[\w-]+:)?INTERFACE>\s*([A-Z0-9_/]{1,30})\s*<\/(?:[\w-]+:)?INTERFACE>/i.exec(formXml.toString('utf8'));
  return match ? match[1].toUpperCase() : undefined;
}

// Namespaced names (/XYZ/...) are not valid file names
function safeName(name: string): string {
  return name.trim().toUpperCase().replace(/\//g, '#');
}

function stamp(now: Date): string {
  return now.toISOString().slice(0, 19).replace(/-|:/g, '').replace('T', '_');
}

export function formFileNames(name: string): { form: string; layout: string } {
  return { form: `${safeName(name)}.form.xml`, layout: `${safeName(name)}.xdp` };
}

export function interfaceFileName(name: string): string {
  return `${safeName(name)}.interface.xml`;
}

export function backupFileNames(name: string, now: Date = new Date()): { form: string; layout: string } {
  return formFileNames(`${name}_${stamp(now)}`);
}
