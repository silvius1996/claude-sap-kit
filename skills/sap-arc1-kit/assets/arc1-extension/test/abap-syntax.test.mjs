// Syntax check of the ABAP sources against SAP_BASIS 7.50, with abaplint (a dependency of ARC-1).
// It knows the syntax of the release, not the signatures of the SAP objects: a clean run does not
// replace the activation on a real system.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Config, MemoryFile, Registry, Version } from '@abaplint/core';

const ABAP_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'abap');

// Classes only: the function modules are kept in the ADT format (signature in the FUNCTION statement),
// which abaplint does not read
// abaplint recognizes the files by their abapGit name: <class>.clas.abap, <class>.clas.testclasses.abap
function abapGitName(name) {
  return name.toLowerCase().replace(/^([^.]+)\.testclasses\.abap$/, '$1.clas.testclasses.abap');
}

function classFiles() {
  const dir = join(ABAP_DIR, 'clas');
  return readdirSync(dir)
    .filter((name) => name.endsWith('.abap'))
    .map((name) => new MemoryFile(abapGitName(name), readFileSync(join(dir, name), 'utf8')));
}

test('ABAP classes: no syntax error with the 7.50 syntax', () => {
  const config = Config.getDefault(Version.v750).get();
  config.rules = { parser_error: true };
  const registry = new Registry(new Config(JSON.stringify(config)));
  const files = classFiles();
  assert.ok(files.length >= 12, `ABAP classes not found in ${ABAP_DIR}`);
  for (const file of files) registry.addFile(file);
  const issues = registry
    .parse()
    .findIssues()
    .map((issue) => `${issue.getFilename()}:${issue.getStart().getRow()} ${issue.getMessage()}`);
  assert.deepEqual(issues, []);
});
