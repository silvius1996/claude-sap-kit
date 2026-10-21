import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compareFormXml, formatAdobePrepareSummary, readAdobePrepareResponse } from '../dist/adobe-replace.js';

const FORM = (name, extra = '') =>
  Buffer.from(
    [
      '<?xml version="1.0" encoding="utf-8"?>',
      '<asx:abap xmlns:asx="http://www.sap.com/abapxml">',
      ' <NAME>' + name + '</NAME>',
      ' <INTERFACE>ZSD_IF_ORDER</INTERFACE>',
      ' <LASTUSER>' + (name.startsWith('ZAI_') ? 'DEVUSER2' : 'DEVUSER1') + '</LASTUSER>',
      ' <LASTDATE>2026-10-2' + (name.startsWith('ZAI_') ? '1' : '0') + '</LASTDATE>',
      ' <CACHE_INFO/>',
      ' <NODE id="o1">',
      '  <FIELD>HEADER-VBELN</FIELD>',
      extra,
      ' </NODE>',
      '</asx:abap>',
    ].join('\n'),
  );
const LAYOUT = Buffer.from('<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/"><template/></xdp:xdp>');
const BODY =
  '<n0:ZAI_ADOBE_FORM_REPLACE.Response>' +
  '<EV_AUTHOR>DEVUSER1</EV_AUTHOR><EV_DEVCLASS>ZSD_FORMS</EV_DEVCLASS><EV_ERROR></EV_ERROR><EV_FM_NAME></EV_FM_NAME>' +
  `<EV_FORM>${FORM('ZSD_ORDER').toString('base64')}</EV_FORM><EV_LASTUSER>DEVUSER1</EV_LASTUSER>` +
  `<EV_LAYOUT>${LAYOUT.toString('base64')}</EV_LAYOUT><EV_TOKEN>WlNEX0ZPUk1TfERFVlVTRVIx</EV_TOKEN>` +
  '<EV_TR_OWNER>DEVUSER2</EV_TR_OWNER>' +
  '</n0:ZAI_ADOBE_FORM_REPLACE.Response>';

test('readAdobePrepareResponse reads data, form XML and layout', () => {
  const r = readAdobePrepareResponse(BODY);
  assert.equal(r.devclass, 'ZSD_FORMS');
  assert.equal(r.author, 'DEVUSER1');
  assert.equal(r.lastUser, 'DEVUSER1');
  assert.equal(r.trOwner, 'DEVUSER2');
  assert.equal(r.token, 'WlNEX0ZPUk1TfERFVlVTRVIx');
  assert.deepEqual(r.form, FORM('ZSD_ORDER'));
  assert.deepEqual(r.layout, LAYOUT);
});

test('readAdobePrepareResponse without token or with a non-XDP layout is an error', () => {
  assert.throws(() => readAdobePrepareResponse(BODY.replace(/<EV_TOKEN>.*<\/EV_TOKEN>/, '<EV_TOKEN></EV_TOKEN>')), /token/);
  assert.throws(() => readAdobePrepareResponse(BODY.replace(/<EV_LAYOUT>.*<\/EV_LAYOUT>/, '<EV_LAYOUT></EV_LAYOUT>')), /not an XDP/);
});

test('compareFormXml: an unchanged copy is the same, name and administrative data aside', () => {
  assert.deepEqual(compareFormXml(FORM('ZSD_ORDER'), FORM('ZAI_SD_ORDER'), 'ZSD_ORDER', 'zai_sd_order'), []);
});

test('compareFormXml: the copy name is replaced only as a whole name', () => {
  const original = Buffer.from('<A>\n <NAME>ZSD_ORDER</NAME>\n <TEXT>ZAI_SD_ORDER_LOGO</TEXT>\n</A>');
  const copy = Buffer.from('<A>\n <NAME>ZAI_SD_ORDER</NAME>\n <TEXT>ZAI_SD_ORDER_LOGO</TEXT>\n</A>');
  assert.deepEqual(compareFormXml(original, copy, 'ZSD_ORDER', 'ZAI_SD_ORDER'), []);
});

test('compareFormXml: the layouts per language (LAYOUTT) belong to the layout and are not compared', () => {
  const layoutt = (text) =>
    ['  <LAYOUTT>', '   <FPLAYOUTT>', '    <LANGUAGE>D</LANGUAGE>', `    <LAYOUT>${text}</LAYOUT>`, '   </FPLAYOUTT>', '  </LAYOUTT>'].join('\n');
  const original = Buffer.from(FORM('ZSD_ORDER').toString('utf8').replace(' <CACHE_INFO/>', layoutt('UGluaw==') + '\n <CACHE_INFO/>'));
  const copy = Buffer.from(FORM('ZAI_SD_ORDER').toString('utf8').replace(' <CACHE_INFO/>', layoutt('Qmx1ZQ==') + '\n <CACHE_INFO/>'));
  assert.deepEqual(compareFormXml(original, copy, 'ZSD_ORDER', 'ZAI_SD_ORDER'), []);
  // The lines after the block keep their numbers in the file
  const changed = Buffer.from(copy.toString('utf8').replace('HEADER-VBELN', 'HEADER-ERDAT'));
  assert.equal(compareFormXml(original, changed, 'ZSD_ORDER', 'ZAI_SD_ORDER')[1], 'original line 15: <FIELD>HEADER-VBELN</FIELD>');
});

test('compareFormXml: a change in the context is reported with its lines', () => {
  const differences = compareFormXml(FORM('ZSD_ORDER'), FORM('ZAI_SD_ORDER', '  <FIELD>HEADER-ERDAT</FIELD>'), 'ZSD_ORDER', 'ZAI_SD_ORDER');
  assert.equal(differences.length, 2);
  assert.equal(differences[0], '0 line(s) of the original and 1 of the copy differ');
  assert.equal(differences[1], 'copy line 10: <FIELD>HEADER-ERDAT</FIELD>');
});

test('compareFormXml: another interface is a difference', () => {
  const copy = Buffer.from(FORM('ZAI_SD_ORDER').toString('utf8').replace('ZSD_IF_ORDER', 'ZAI_SD_IF_ORDER'));
  const differences = compareFormXml(FORM('ZSD_ORDER'), copy, 'ZSD_ORDER', 'ZAI_SD_ORDER');
  assert.deepEqual(differences, [
    '1 line(s) of the original and 1 of the copy differ',
    'original line 4: <INTERFACE>ZSD_IF_ORDER</INTERFACE>',
    'copy line 4: <INTERFACE>ZAI_SD_IF_ORDER</INTERFACE>',
  ]);
});

test('formatAdobePrepareSummary lists everything needed to confirm', () => {
  const text = formatAdobePrepareSummary({
    original: 'ZSD_ORDER',
    copy: 'ZAI_SD_ORDER',
    transport: 'DEVK900010',
    backup: ['C:\\x\\ZSD_ORDER_20261021_100000.form.xml', 'C:\\x\\ZSD_ORDER_20261021_100000.xdp'],
    result: readAdobePrepareResponse(BODY),
  });
  for (const part of ['layout of ZSD_ORDER ← ZAI_SD_ORDER', 'ZSD_FORMS', 'owner DEVUSER2', '.xdp', 'other languages', 'Token: WlNE', 'action=execute']) {
    assert.ok(text.includes(part), part);
  }
});
