import { join } from 'node:path';
import { z } from 'zod';
import { defineTool, OperationType, type ToolContext } from 'arc-1/public';
import { savePdf as saveFile } from '../pdf-file.js';
import { backupFileName, decodeXml, readLocalFile } from '../smartform-file.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';
import { DEFAULT_SMARTFORM_DIR } from './Custom_SmartFormRead.js';

// Uploads a local XML as a ZAI_* SmartForms in $TMP: check, active save, generation of the
// function module. Before overwriting it saves a backup of the active version.
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
const HEADERS = { SOAPAction: 'urn:sap-com:document:sap:rfc:functions', Accept: 'text/xml' };

const schema = z.object({
  name: z.string().min(1).max(30).describe('Target SmartForms: must start with ZAI_ (created in $TMP if it does not exist).'),
  file: z.string().min(1).describe('Path of the XML file to upload (usually downloaded with Custom_SmartFormRead).'),
});

type Args = z.infer<typeof schema>;

async function callRfc(ctx: ToolContext, fm: string, params: Record<string, string>): Promise<string> {
  const res = await ctx.http.post(SOAP_RFC_PATH, buildEnvelope(fm, params), 'text/xml; charset=utf-8', HEADERS);
  const fault = readFault(res.body);
  if (fault || res.statusCode !== 200) {
    throw new Error(`SOAP-RFC call failed (HTTP ${res.statusCode}): ${fault ?? res.body.slice(0, 2000)}`);
  }
  return res.body;
}

export default defineTool({
  name: 'Custom_SmartFormWrite',
  description:
    'Uploads an XML file as a ZAI_* SmartForms in $TMP: checks it, saves the active version and generates the function module. ' +
    'Refuses non-ZAI_* names and forms of other authors or outside $TMP. Before overwriting it saves an XML backup ' +
    'in output/smartforms/backup. Never deletes forms and never uses transport requests.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    const name = a.name.trim().toUpperCase();
    try {
      const xml = await readLocalFile(a.file);
      decodeXml(xml.toString('base64'));

      // Backup of the current version, if the form already exists
      let backup = '';
      const current = await callRfc(ctx, 'ZAI_SMARTFORM_READ', { IV_NAME: name });
      if (!readElement(current, 'EV_ERROR')) {
        backup = await saveFile(join(DEFAULT_SMARTFORM_DIR, 'backup'), backupFileName(name), decodeXml(readElement(current, 'EV_XML')));
      }

      const body = await callRfc(ctx, 'ZAI_SMARTFORM_WRITE', { IV_NAME: name, IV_XML: xml.toString('base64') });
      const error = readElement(body, 'EV_ERROR');
      if (error) {
        return { isError: true, content: [{ type: 'text', text: error + (backup ? `\nBackup (version in SAP unchanged): ${backup}` : '') }] };
      }
      const lines = [
        `SmartForms ${name} ${readElement(body, 'EV_CREATED').trim() ? 'created in $TMP' : 'updated'} and active`,
        `Function module: ${readElement(body, 'EV_FM_NAME').trim()}`,
        `Backup of the previous version: ${backup || '- (new form)'}`,
      ];
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    } catch (e) {
      return { isError: true, content: [{ type: 'text', text: (e as Error).message }] };
    }
  },
});
