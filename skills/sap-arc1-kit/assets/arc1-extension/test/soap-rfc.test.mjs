import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildEnvelope, readElement, readFault, readItems } from '../dist/soap-rfc.js';

test('envelope with simple and table parameters, escaped values', () => {
  const xml = buildEnvelope('ZAI_RUN_REPORT', {
    IV_TCODE: 'MB52',
    IV_VARIANT: undefined,
    IT_PARAMS: [{ SELNAME: 'MATNR', KIND: 'S', SIGN: 'I', OPTION: 'CP', LOW: 'A&B<*', HIGH: '' }],
  });
  assert.match(xml, /<urn:ZAI_RUN_REPORT xmlns:urn="urn:sap-com:document:sap:rfc:functions">/);
  assert.match(xml, /<IV_TCODE>MB52<\/IV_TCODE>/);
  assert.doesNotMatch(xml, /IV_VARIANT/);
  assert.match(xml, /<IT_PARAMS><item><SELNAME>MATNR<\/SELNAME><KIND>S<\/KIND>.*<LOW>A&amp;B&lt;\*<\/LOW><HIGH><\/HIGH><\/item><\/IT_PARAMS>/);
});

test('reading the response: elements, table and fault', () => {
  const body =
    '<soap-env:Body><n0:ZAI_RUN_REPORTResponse><EV_OUTPUT_TYPE>LIST</EV_OUTPUT_TYPE>' +
    '<EV_DATA_JSON>[{&quot;A&quot;:1}]</EV_DATA_JSON><ET_LIST><item>line  1</item><item>a &amp; b</item></ET_LIST>' +
    '</n0:ZAI_RUN_REPORTResponse></soap-env:Body>';
  assert.equal(readElement(body, 'EV_OUTPUT_TYPE'), 'LIST');
  assert.equal(readElement(body, 'EV_DATA_JSON'), '[{"A":1}]');
  assert.deepEqual(readItems(body, 'ET_LIST'), ['line  1', 'a & b']);
  assert.equal(readFault(body), undefined);
  assert.equal(
    readFault('<soap-env:Fault><faultcode>soap-env:Client</faultcode><faultstring>NO_AUTH</faultstring></soap-env:Fault>'),
    'NO_AUTH',
  );
});
