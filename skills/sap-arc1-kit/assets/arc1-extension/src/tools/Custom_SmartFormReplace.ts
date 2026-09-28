import { join } from 'node:path';
import { z } from 'zod';
import { defineTool, OperationType, type ToolContext } from 'arc-1/public';
import { savePdf as saveFile } from '../pdf-file.js';
import { checkReplaceRules, readRules } from '../project-rules.js';
import { backupFileName } from '../smartform-file.js';
import { formatPrepareSummary, readPrepareResponse, type PrepareResult } from '../smartform-replace.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';
import { DEFAULT_SMARTFORM_DIR } from './Custom_SmartFormRead.js';

// Replaces a customer SmartForms (Z*/Y*) with the ZAI_* copy approved in preview, under a transport
// request. Two steps: prepare (backup + summary + token, no writes) and execute (with the token).
const FUNCTION_NAME = 'ZAI_SMARTFORM_REPLACE';
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
const HEADERS = { SOAPAction: 'urn:sap-com:document:sap:rfc:functions', Accept: 'text/xml' };

const schema = z.object({
  action: z.enum(['prepare', 'execute']).describe('prepare: backup and summary, no writes. execute: replacement, after explicit confirmation.'),
  original: z.string().min(1).max(30).describe('Customer SmartForms to replace (Z* or Y*).'),
  copy: z.string().min(1).max(30).describe('ZAI_* copy already checked in preview by the user.'),
  transport: z.string().min(1).max(20).describe('Transport request given by the user.'),
  token: z.string().optional().describe('execute only: token returned by prepare.'),
});

type Args = z.infer<typeof schema>;

async function callReplace(ctx: ToolContext, params: Record<string, string>): Promise<string> {
  const res = await ctx.http.post(SOAP_RFC_PATH, buildEnvelope(FUNCTION_NAME, params), 'text/xml; charset=utf-8', HEADERS);
  const fault = readFault(res.body);
  if (fault || res.statusCode !== 200) {
    throw new Error(`SOAP-RFC call failed (HTTP ${res.statusCode}): ${fault ?? res.body.slice(0, 2000)}`);
  }
  const error = readElement(res.body, 'EV_ERROR');
  if (error) throw new Error(error);
  return res.body;
}

function fail(text: string) {
  return { isError: true, content: [{ type: 'text' as const, text }] };
}

export default defineTool({
  name: 'Custom_SmartFormReplace',
  description:
    'Replaces a customer SmartForms (Z*/Y*) with the ZAI_* copy checked in preview, recording it in the ' +
    'given transport request. prepare: saves an XML backup of the original and returns a summary and a token, ' +
    'without writing to SAP. execute: only after explicit confirmation by the user, with the token from prepare; ' +
    'refused if the original or the copy changed in the meantime. Rules from the project .mcp.json ' +
    '(SAP_ALLOWED_PACKAGES, ZAI_CHECK_AUTHOR, ZAI_ALLOWED_TRANSPORTS). Never standard forms; never releases the request.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    const original = a.original.trim().toUpperCase();
    const copy = a.copy.trim().toUpperCase();
    const transport = a.transport.trim().toUpperCase();
    const rules = readRules();
    if (!rules.transportWrites) {
      return fail('SAP_ALLOW_TRANSPORT_WRITES is not true in the project .mcp.json: replacement not allowed');
    }
    if (a.action === 'execute' && !a.token?.trim()) {
      return fail('execute requires the token returned by prepare');
    }

    // The author check is done in ABAP with the logged-on user; .mcp.json only says whether to do it
    const base = { IV_ORIGINAL: original, IV_COPY: copy, IV_TRANSPORT: transport, IV_CHECK_AUTHOR: rules.checkAuthor ? 'X' : '' };
    try {
      // execute reads the state again too: package and author may have changed after prepare
      const prepared: PrepareResult = readPrepareResponse(await callReplace(ctx, { ...base, IV_MODE: 'P' }));
      const errors = checkReplaceRules(rules, { devclass: prepared.devclass, transport });
      if (errors.length) return fail(`Replacement refused by the project rules:\n- ${errors.join('\n- ')}`);

      // Backup in execute too: the XML has already been read and an earlier prepare may not have left the file
      const backup = await saveFile(join(DEFAULT_SMARTFORM_DIR, 'backup'), backupFileName(original), prepared.xml);
      if (a.action === 'prepare') {
        return { content: [{ type: 'text', text: formatPrepareSummary({ original, copy, transport, backup, result: prepared }) }] };
      }

      const body = await callReplace(ctx, { ...base, IV_MODE: 'E', IV_TOKEN: a.token!.trim() });
      const fmName = readElement(body, 'EV_FM_NAME').trim();
      if (!fmName) throw new Error(`Replacement result not confirmed by SAP: check ${original} in transaction SMARTFORMS`);
      const lines = [
        `SmartForms ${original} replaced with ${copy}, active and generated`,
        `Function module: ${fmName}`,
        `Recorded in transport request ${transport} (not released)`,
        `Backup of the replaced version: ${backup}`,
        'To roll back: upload the backup into a ZAI_* copy and run prepare + execute again',
      ];
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    } catch (e) {
      return fail((e as Error).message);
    }
  },
});
