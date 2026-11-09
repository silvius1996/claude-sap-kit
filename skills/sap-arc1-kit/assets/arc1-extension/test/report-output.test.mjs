import test from 'node:test';
import assert from 'node:assert/strict';
import { formatRows } from '../dist/report-output.js';

test('rows already cut by the FM: the total comes from EV_ROW_COUNT', () => {
  const out = formatRows([1, 2, 3], 1200, 3);
  assert.deepEqual(out.shown, [1, 2, 3]);
  assert.equal(out.summary, 'Rows: 1200 (showing the first 3)');
});

test('all rows returned: no note', () => {
  assert.equal(formatRows(['a', 'b'], 2, 200).summary, 'Rows: 2');
});

test('rows not cut by the FM (hashed table): cut here', () => {
  const out = formatRows([1, 2, 3, 4, 5], 5, 2);
  assert.deepEqual(out.shown, [1, 2]);
  assert.equal(out.summary, 'Rows: 5 (showing the first 2)');
});

test('missing or wrong total: the rows received count', () => {
  assert.equal(formatRows([1, 2, 3], Number.NaN, 2).summary, 'Rows: 3 (showing the first 2)');
  assert.equal(formatRows([1, 2, 3], 0, 200).summary, 'Rows: 3');
});
