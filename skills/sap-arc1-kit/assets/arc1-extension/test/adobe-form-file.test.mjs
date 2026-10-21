import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  backupFileNames,
  backupInterfaceFileName,
  checkFormXml,
  checkInterfaceXml,
  checkLayout,
  checkWritableName,
  decodeFormXml,
  decodeLayout,
  findInterfaceName,
  formFileNames,
  interfaceFileName,
} from '../dist/adobe-form-file.js';

const FORM = Buffer.from('<?xml version="1.0" encoding="utf-8"?>\n<asx:abap xmlns:asx="http://www.sap.com/abapxml">\n <INTERFACE>FP_TEST_IF_00</INTERFACE>\n</asx:abap>');
const LAYOUT = Buffer.from('<?xml version="1.0" encoding="UTF-8"?>\n<?xfa generator="AdobeLiveCycleDesigner"?>\n<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/"><template/></xdp:xdp>');

test('file names: form, layout and interface, upper case and without slashes', () => {
  assert.deepEqual(formFileNames(' zai_af_order '), { form: 'ZAI_AF_ORDER.form.xml', layout: 'ZAI_AF_ORDER.xdp' });
  assert.deepEqual(formFileNames('/ABC/FORM'), { form: '#ABC#FORM.form.xml', layout: '#ABC#FORM.xdp' });
  assert.equal(interfaceFileName('fp_test_if_00'), 'FP_TEST_IF_00.interface.xml');
});

test('backup file names with UTC date and time', () => {
  const now = new Date(Date.UTC(2026, 9, 19, 14, 5, 9));
  assert.deepEqual(backupFileNames('zai_af_order', now), {
    form: 'ZAI_AF_ORDER_20261019_140509.form.xml',
    layout: 'ZAI_AF_ORDER_20261019_140509.xdp',
  });
});

test('form XML: any XML is accepted, other content is refused', () => {
  assert.deepEqual(decodeFormXml(FORM.toString('base64')), FORM);
  assert.deepEqual(checkFormXml(Buffer.concat([Buffer.from('﻿  '), FORM])).length, FORM.length + 5);
  assert.throws(() => decodeFormXml(''), /not an XML/);
  assert.throws(() => checkFormXml(Buffer.from('%PDF-1.7')), /not an XML/);
});

test('layout: only XDP is accepted', () => {
  assert.deepEqual(decodeLayout(LAYOUT.toString('base64')), LAYOUT);
  assert.throws(() => checkLayout(Buffer.from('<template/>')), /not an XDP/);
  assert.throws(() => decodeLayout(''), /not an XDP/);
});

test('interface XML: object reference required, the form XML is refused', () => {
  const xml = Buffer.from('<?xml version="1.0"?>\n<asx:abap>\n <asx:values>\n  <INTERFACE href="#o46"/>\n </asx:values>\n</asx:abap>');
  assert.deepEqual(checkInterfaceXml(xml), xml);
  assert.throws(() => checkInterfaceXml(FORM), /not the XML of a form interface/);
  assert.throws(() => checkInterfaceXml(Buffer.from('%PDF-1.7')), /not an XML/);
  const now = new Date(Date.UTC(2026, 9, 20, 8, 1, 2));
  assert.equal(backupInterfaceFileName('zai_af_test_if', now), 'ZAI_AF_TEST_IF_20261020_080102.interface.xml');
});

test('interface name read from the form XML, with or without namespace prefix', () => {
  assert.equal(findInterfaceName(FORM), 'FP_TEST_IF_00');
  assert.equal(findInterfaceName(Buffer.from('<x:INTERFACE> /abc/if_order </x:INTERFACE>')), '/ABC/IF_ORDER');
  assert.equal(findInterfaceName(Buffer.from('<FORM><NAME>X</NAME></FORM>')), undefined);
});

test('writable names: only ZAI_*, checked before any call', () => {
  assert.equal(checkWritableName(' zai_af_test_if ', 'interface'), 'ZAI_AF_TEST_IF');
  assert.equal(checkWritableName('ZAI_AF_TEST', 'form'), 'ZAI_AF_TEST');
  assert.throws(() => checkWritableName('SDOC_INTERFACE', 'interface'), /form interfaces ZAI_\*: SDOC_INTERFACE refused/);
  assert.throws(() => checkWritableName('ZSD_FORM', 'form'), /Adobe forms ZAI_\*: ZSD_FORM refused/);
});
