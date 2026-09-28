import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatPrepareSummary, formatSapDateTime, readPrepareResponse } from '../dist/smartform-replace.js';

const XML = Buffer.from('<sf:SMARTFORM xmlns:sf="urn:sap-com:SmartForms:2000:internal-structure"/>');
const BODY =
  '<n0:ZAI_SMARTFORM_REPLACE.Response>' +
  '<EV_AUTHOR>DEVUSER1</EV_AUTHOR><EV_DEVCLASS>ZSD_FORMS</EV_DEVCLASS>' +
  '<EV_ERROR></EV_ERROR><EV_FM_NAME></EV_FM_NAME>' +
  '<EV_LASTDATE>2026-09-27</EV_LASTDATE><EV_LASTTIME>18:07:57</EV_LASTTIME><EV_LASTUSER>DEVUSER1</EV_LASTUSER>' +
  '<EV_TR_OWNER>DEVUSER2</EV_TR_OWNER>' +
  `<EV_TOKEN>MXwyMDI2MDkyN3wxODA3NTc=</EV_TOKEN><EV_XML>${XML.toString('base64')}</EV_XML>` +
  '</n0:ZAI_SMARTFORM_REPLACE.Response>';

test('formatSapDateTime accepts both SOAP formats', () => {
  assert.equal(formatSapDateTime('2026-09-27', '18:07:57'), '27.09.2026 18:07');
  assert.equal(formatSapDateTime('20260927', '180757'), '27.09.2026 18:07');
  assert.equal(formatSapDateTime('', ''), '-');
});

test('readPrepareResponse reads data and XML', () => {
  const r = readPrepareResponse(BODY);
  assert.equal(r.devclass, 'ZSD_FORMS');
  assert.equal(r.author, 'DEVUSER1');
  assert.equal(r.lastUser, 'DEVUSER1');
  assert.equal(r.trOwner, 'DEVUSER2');
  assert.equal(r.token, 'MXwyMDI2MDkyN3wxODA3NTc=');
  assert.deepEqual(r.xml, XML);
});

test('readPrepareResponse without token is an error', () => {
  assert.throws(() => readPrepareResponse(BODY.replace(/<EV_TOKEN>.*<\/EV_TOKEN>/, '<EV_TOKEN></EV_TOKEN>')), /token/);
});

test('formatPrepareSummary lists everything needed to confirm', () => {
  const text = formatPrepareSummary({
    original: 'ZSF_DELNOTE',
    copy: 'ZAI_TOOLTEST2',
    transport: 'DEVK900010',
    backup: 'C:\\x\\ZSF_DELNOTE_20260927_180800.xml',
    result: readPrepareResponse(BODY),
  });
  for (const part of ['ZSF_DELNOTE', 'ZAI_TOOLTEST2', 'DEVK900010', 'ZSD_FORMS', '27.09.2026 18:07', 'DEVUSER1', '_20260927_180800.xml', 'MXwyMDI2MDkyN3wxODA3NTc=', 'owner DEVUSER2']) {
    assert.ok(text.includes(part), `missing ${part}`);
  }
  assert.match(text, /Nothing changed in SAP/);
});
