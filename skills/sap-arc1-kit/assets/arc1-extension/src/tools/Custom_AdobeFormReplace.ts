import { join } from 'node:path';
import { z } from 'zod';
import { defineTool, OperationType, type ToolContext } from 'arc-1/public';
import { backupFileNames, decodeFormXml } from '../adobe-form-file.js';
import { compareFormXml, formatAdobePrepareSummary, readAdobePrepareResponse } from '../adobe-replace.js';
import { savePdf as saveFile } from '../pdf-file.js';
import { checkAuthorFlag, checkReplaceRules, readRules } from '../project-rules.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';
import { callAdobeRead, DEFAULT_ADOBE_DIR } from './Custom_AdobeFormRead.js';

// Gives a customer Adobe form (Z*/Y*) the layout of the ZAI_* copy approved in preview, in place and under a
// transport request. Two steps: prepare (checks, backup, summary, token; no writes) and execute (with the token).
// Only the layout is written: the copy must not differ from the original in anything else.
const FUNCTION_NAME = 'ZAI_ADOBE_FORM_REPLACE';
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
const HEADERS = { SOAPAction: 'urn:sap-com:document:sap:rfc:functions', Accept: 'text/xml' };

const schema = z.object({
  action: z.enum(['prepare', 'execute']).describe('prepare: checks, backup and summary, no writes. execute: replacement, after explicit confirmation.'),
  original: z.string().min(1).max(30).describe('Customer Adobe form to change (Z* or Y*).'),
  copy: z.string().min(1).max(30).describe('ZAI_* copy already checked in preview by the user.'),
  transport: z.string().min(1).max(20).describe('Transport request given by the user (not a task).'),
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
  name: 'Custom_AdobeFormReplace',
  description:
    'Gives a customer Adobe form (Z*/Y*) the layout of the ZAI_* copy checked in preview, in place, recording the ' +
    'form in the given transport request. Only the layout changes: refused if the copy also differs in context, ' +
    'interface or properties. prepare: checks, XML/XDP backup of the original, summary and token, without writing ' +
    'to SAP. execute: only after explicit confirmation by the user, with the token from prepare; refused if the ' +
    'original or the copy changed in the meantime. Rules from the project .mcp.json (SAP_ALLOWED_PACKAGES, ' +
    'ZAI_CHECK_AUTHOR, ZAI_ALLOWED_TRANSPORTS). Never standard forms; never releases the request.',
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
    if (!copy.startsWith('ZAI_')) {
      return fail(`The copy must be an Adobe form ZAI_*: ${copy} refused`);
    }
    if (a.action === 'execute' && !a.token?.trim()) {
      return fail('execute requires the token returned by prepare');
    }

    // The author check is done in ABAP with the logged-on user; .mcp.json only says whether to do it
    const base = { IV_ORIGINAL: original, IV_COPY: copy, IV_TRANSPORT: transport, IV_CHECK_AUTHOR: checkAuthorFlag(rules) };
    try {
      // execute reads the state again too: package, author and the two forms may have changed after prepare
      const prepared = readAdobePrepareResponse(await callReplace(ctx, { ...base, IV_MODE: 'P' }));
      const errors = checkReplaceRules(rules, { devclass: prepared.devclass, transport });
      if (errors.length) return fail(`Replacement refused by the project rules:\n- ${errors.join('\n- ')}`);

      const copyRead = await callAdobeRead(ctx, { IV_NAME: copy });
      const readError = readElement(copyRead, 'EV_ERROR');
      if (readError) throw new Error(readError);
      const differences = compareFormXml(prepared.form, decodeFormXml(readElement(copyRead, 'EV_FORM')), original, copy);
      if (differences.length) {
        return fail(
          `Replacement refused: ${copy} differs from ${original} outside the layout, and only the layout is replaced. ` +
            'Bring the other changes (context, interface, properties) into the original in SFP, or ask the user.\n' +
            differences.join('\n'),
        );
      }

      // Backup in execute too: the files have already been read and an earlier prepare may not have left them
      const files = backupFileNames(original);
      const dir = join(DEFAULT_ADOBE_DIR, 'backup');
      const backup = [await saveFile(dir, files.form, prepared.form), await saveFile(dir, files.layout, prepared.layout)];
      if (a.action === 'prepare') {
        return { content: [{ type: 'text', text: formatAdobePrepareSummary({ original, copy, transport, backup, result: prepared }) }] };
      }

      const body = await callReplace(ctx, { ...base, IV_MODE: 'E', IV_TOKEN: a.token!.trim() });
      const fmName = readElement(body, 'EV_FM_NAME').trim();
      if (!fmName) throw new Error(`Replacement result not confirmed by SAP: check ${original} in transaction SFP`);
      const lines = [
        `Adobe form ${original}: layout replaced with that of ${copy}, active`,
        `Function module: ${fmName}`,
        `Recorded in transport request ${transport} (not released)`,
        `Backup of the replaced version: ${backup.join(', ')}`,
        'To roll back: upload the backup into a ZAI_* copy with Custom_AdobeFormWrite and run prepare + execute again',
      ];
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    } catch (e) {
      return fail((e as Error).message);
    }
  },
});
