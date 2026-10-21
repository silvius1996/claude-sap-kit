import { join } from 'node:path';
import { z } from 'zod';
import { defineTool, OperationType, type ToolContext } from 'arc-1/public';
import { backupInterfaceFileName, checkInterfaceXml, checkWritableName, decodeFormXml } from '../adobe-form-file.js';
import { savePdf as saveFile } from '../pdf-file.js';
import { readLocalFile } from '../smartform-file.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';
import { callAdobeRead, DEFAULT_ADOBE_DIR } from './Custom_AdobeFormRead.js';

// Uploads an interface XML as a ZAI_* form interface in $TMP and activates it. An existing ZAI_* interface is
// updated in place (parameters, global data, types, coding, reference fields), so the forms using it stay linked.
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
const HEADERS = { SOAPAction: 'urn:sap-com:document:sap:rfc:functions', Accept: 'text/xml' };

const schema = z.object({
  name: z.string().min(1).max(30).describe('Target form interface: must start with ZAI_ (created in $TMP if it does not exist).'),
  interface: z.string().min(1).describe('Path of the interface XML (usually <NAME>.interface.xml downloaded with Custom_AdobeFormRead).'),
});

type Args = z.infer<typeof schema>;

async function callWrite(ctx: ToolContext, params: Record<string, string>): Promise<string> {
  const res = await ctx.http.post(SOAP_RFC_PATH, buildEnvelope('ZAI_ADOBE_INTERFACE_WRITE', params), 'text/xml; charset=utf-8', HEADERS);
  const fault = readFault(res.body);
  if (fault || res.statusCode !== 200) {
    throw new Error(`SOAP-RFC call failed (HTTP ${res.statusCode}): ${fault ?? res.body.slice(0, 2000)}`);
  }
  return res.body;
}

export default defineTool({
  name: 'Custom_AdobeInterfaceWrite',
  description:
    'Uploads an interface XML (parameters, global data, types, initialization coding) as a ZAI_* form interface in ' +
    '$TMP and activates it. An existing ZAI_* interface is updated in place, so the forms using it stay linked; its ' +
    'current version is saved first in output/adobe-forms/backup. Refuses non-ZAI_* names, interfaces of other ' +
    'authors or outside $TMP, XML schema based interfaces and a change of interface type. Never writes customer or ' +
    'standard interfaces, never uses transport requests. To use it in a form, set <INTERFACE> in the form XML.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    try {
      const name = checkWritableName(a.name, 'interface');
      const xml = checkInterfaceXml(await readLocalFile(a.interface));

      // Backup of the current version, if the interface already exists
      let backup = '';
      const current = await callAdobeRead(ctx, { IV_INTERFACE: name });
      if (!readElement(current, 'EV_ERROR')) {
        backup = await saveFile(join(DEFAULT_ADOBE_DIR, 'backup'), backupInterfaceFileName(name), decodeFormXml(readElement(current, 'EV_INTERFACE')));
      }

      const body = await callWrite(ctx, { IV_NAME: name, IV_INTERFACE: xml.toString('base64') });
      const error = readElement(body, 'EV_ERROR');
      if (error) {
        return { isError: true, content: [{ type: 'text', text: error + (backup ? `\nBackup: ${backup}` : '') }] };
      }
      const lines = [
        `Form interface ${name} ${readElement(body, 'EV_CREATED').trim() ? 'created in $TMP' : 'updated in place'} and active`,
        `Backup of the previous version: ${backup || '- (new interface)'}`,
      ];
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    } catch (e) {
      return { isError: true, content: [{ type: 'text', text: (e as Error).message }] };
    }
  },
});
