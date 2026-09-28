// Calls a remote-enabled function module through the standard SAP service
// /sap/bc/soap/rfc: SOAP envelope in, <FM>.Response out.

export interface RsParam {
  SELNAME: string;
  KIND: string;
  SIGN: string;
  OPTION: string;
  LOW: string;
  HIGH: string;
}

export type RfcValue = string | RsParam[] | undefined;

const RFC_NS = 'urn:sap-com:document:sap:rfc:functions';

export function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export function unescapeXml(value: string): string {
  return value
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code: string) => String.fromCodePoint(parseInt(code, 16)))
    .replace(/&amp;/g, '&');
}

function serializeParam(name: string, value: RfcValue): string {
  if (value === undefined || value === '') return '';
  if (typeof value === 'string') return `<${name}>${escapeXml(value)}</${name}>`;
  const items = value
    .map(
      (row) =>
        '<item>' +
        (Object.keys(row) as (keyof RsParam)[]).map((key) => `<${key}>${escapeXml(row[key])}</${key}>`).join('') +
        '</item>',
    )
    .join('');
  return `<${name}>${items}</${name}>`;
}

export function buildEnvelope(functionName: string, params: Record<string, RfcValue>): string {
  const body = Object.entries(params)
    .map(([name, value]) => serializeParam(name, value))
    .join('');
  return (
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<soap-env:Envelope xmlns:soap-env="http://schemas.xmlsoap.org/soap/envelope/">' +
    `<soap-env:Body><urn:${functionName} xmlns:urn="${RFC_NS}">${body}</urn:${functionName}>` +
    '</soap-env:Body></soap-env:Envelope>'
  );
}

/** Value of a simple element (without namespace prefix) in the response. */
export function readElement(xml: string, name: string): string {
  const match = new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(xml);
  return match ? unescapeXml(match[1]) : '';
}

/** <item> rows of a table parameter with a simple line type (e.g. STRING_TABLE). */
export function readItems(xml: string, name: string): string[] {
  const block = new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(xml);
  if (!block) return [];
  return [...block[1].matchAll(/<item>([\s\S]*?)<\/item>/g)].map((m) => unescapeXml(m[1]));
}

/** Text of a SOAP fault (RFC exceptions, authorization errors, dumps), if any. */
export function readFault(xml: string): string | undefined {
  if (!/Fault>/.test(xml)) return undefined;
  const text = readElement(xml, 'faultstring') || readElement(xml, 'message');
  return text || 'SOAP fault without description';
}
