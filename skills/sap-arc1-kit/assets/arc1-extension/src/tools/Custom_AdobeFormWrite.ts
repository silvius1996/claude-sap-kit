import { join } from 'node:path';
import { z } from 'zod';
import { defineTool, OperationType, type ToolContext } from 'arc-1/public';
import { backupFileNames, checkFormXml, checkLayout, checkWritableName, decodeFormXml, decodeLayout } from '../adobe-form-file.js';
import { savePdf as saveFile } from '../pdf-file.js';
import { readLocalFile } from '../smartform-file.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';
import { callAdobeRead, DEFAULT_ADOBE_DIR } from './Custom_AdobeFormRead.js';

// Uploads form XML + layout XDP as a ZAI_* Adobe form in $TMP: save, activation, function module.
// The SAP API cannot replace the context of a form: an existing ZAI_* copy is deleted and created again,
// after a local backup. The ABAP side renews the timeStamp of the XDP, so ADS does not print a cached layout.
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
const HEADERS = { SOAPAction: 'urn:sap-com:document:sap:rfc:functions', Accept: 'text/xml' };

const schema = z.object({
  name: z.string().min(1).max(30).describe('Target Adobe form: must start with ZAI_ (created in $TMP if it does not exist).'),
  form: z.string().min(1).describe('Path of the form XML (usually <NAME>.form.xml downloaded with Custom_AdobeFormRead).'),
  layout: z.string().min(1).describe('Path of the layout XDP (usually <NAME>.xdp downloaded with Custom_AdobeFormRead).'),
});

type Args = z.infer<typeof schema>;

async function callWrite(ctx: ToolContext, params: Record<string, string>): Promise<string> {
  const res = await ctx.http.post(SOAP_RFC_PATH, buildEnvelope('ZAI_ADOBE_FORM_WRITE', params), 'text/xml; charset=utf-8', HEADERS);
  const fault = readFault(res.body);
  if (fault || res.statusCode !== 200) {
    throw new Error(`SOAP-RFC call failed (HTTP ${res.statusCode}): ${fault ?? res.body.slice(0, 2000)}`);
  }
  return res.body;
}

export default defineTool({
  name: 'Custom_AdobeFormWrite',
  description:
    'Uploads a form XML and its layout XDP as a ZAI_* Adobe form in $TMP: saves it, activates it and generates the ' +
    'function module. Needs Adobe Document Services (ADS). Refuses non-ZAI_* names and forms of other authors or ' +
    'outside $TMP. An existing ZAI_* copy is deleted and created again (the SAP API cannot replace the context of a ' +
    'form), after an XML/XDP backup in output/adobe-forms/backup. The timeStamp of the XDP is renewed, as Designer ' +
    'does, so that ADS does not print a cached layout. Never writes customer or standard forms, never uses transport requests.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    try {
      const name = checkWritableName(a.name, 'form');
      const form = checkFormXml(await readLocalFile(a.form));
      const layout = checkLayout(await readLocalFile(a.layout));

      // Backup of the current version, if the copy already exists
      const backup: string[] = [];
      const current = await callAdobeRead(ctx, { IV_NAME: name });
      if (!readElement(current, 'EV_ERROR')) {
        const files = backupFileNames(name);
        const dir = join(DEFAULT_ADOBE_DIR, 'backup');
        backup.push(await saveFile(dir, files.form, decodeFormXml(readElement(current, 'EV_FORM'))));
        backup.push(await saveFile(dir, files.layout, decodeLayout(readElement(current, 'EV_LAYOUT'))));
      }

      const body = await callWrite(ctx, { IV_NAME: name, IV_FORM: form.toString('base64'), IV_LAYOUT: layout.toString('base64') });
      const error = readElement(body, 'EV_ERROR');
      if (error) {
        return { isError: true, content: [{ type: 'text', text: error + (backup.length ? `\nBackup: ${backup.join(', ')}` : '') }] };
      }
      const lines = [
        `Adobe form ${name} ${readElement(body, 'EV_CREATED').trim() ? 'created in $TMP' : 'rewritten (deleted and created again)'} and active`,
        `Function module: ${readElement(body, 'EV_FM_NAME').trim()}`,
        `ADS: ${readElement(body, 'EV_ADS_VERSION').trim()}`,
        `Backup of the previous version: ${backup.length ? backup.join(', ') : '- (new form)'}`,
      ];
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    } catch (e) {
      return { isError: true, content: [{ type: 'text', text: (e as Error).message }] };
    }
  },
});
