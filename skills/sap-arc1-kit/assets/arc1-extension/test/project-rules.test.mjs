import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkReplaceRules, matchesPackage, readRules } from '../dist/project-rules.js';

const DEV_RULES = {
  SAP_ALLOW_TRANSPORT_WRITES: 'true',
  SAP_ALLOWED_PACKAGES: '$*,Z*,Y*',
};

test('readRules reads the project variables', () => {
  const r = readRules({ ...DEV_RULES, ZAI_CHECK_AUTHOR: 'false', ZAI_ALLOWED_TRANSPORTS: ' qask900001 , QASK900002 ' });
  assert.equal(r.transportWrites, true);
  assert.deepEqual(r.allowedPackages, ['$*', 'Z*', 'Y*']);
  assert.equal(r.checkAuthor, false);
  assert.deepEqual(r.allowedTransports, ['QASK900001', 'QASK900002']);
});

test('readRules: safe defaults', () => {
  const r = readRules({});
  assert.equal(r.transportWrites, false);
  assert.deepEqual(r.allowedPackages, []);
  assert.equal(r.checkAuthor, true);
  assert.equal(r.allowedTransports, undefined);
});

test('matchesPackage with wildcards and literal $', () => {
  assert.equal(matchesPackage('ZSD_PRINT', ['Z*']), true);
  assert.equal(matchesPackage('$TMP', ['$*']), true);
  assert.equal(matchesPackage('SAPSD', ['Z*', 'Y*']), false);
  assert.equal(matchesPackage('ZSD', []), false);
});

test('checkReplaceRules: package', () => {
  const r = readRules(DEV_RULES);
  assert.deepEqual(checkReplaceRules(r, { devclass: 'ZSD', transport: 'DEVK900010' }), []);
  const errors = checkReplaceRules(r, { devclass: 'SAPSD', transport: 'DEVK900010' });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Package SAPSD not allowed/);
});

test('checkReplaceRules with a shared user: request in the list', () => {
  const r = readRules({ ...DEV_RULES, ZAI_CHECK_AUTHOR: 'false', ZAI_ALLOWED_TRANSPORTS: 'QASK900001' });
  assert.equal(r.checkAuthor, false);
  assert.deepEqual(checkReplaceRules(r, { devclass: 'ZSD', transport: 'qask900001' }), []);
  assert.match(checkReplaceRules(r, { devclass: 'ZSD', transport: 'QASK900099' })[0], /QASK900099 is not among/);
});

test('checkReplaceRules: missing SAP_ALLOWED_PACKAGES blocks everything', () => {
  const r = readRules({ SAP_ALLOW_TRANSPORT_WRITES: 'true' });
  assert.match(checkReplaceRules(r, { devclass: 'ZSD', transport: 'T' })[0], /SAP_ALLOWED_PACKAGES/);
});
