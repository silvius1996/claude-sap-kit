import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { defineTool, OperationType } from 'arc-1/public';
import { savePdf as saveFile } from '../pdf-file.js';
import { decodeXml, xmlFileName } from '../smartform-file.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';

// Downloads the SmartForms as XML (one line per element) into output/smartforms,
// to read it or edit it locally before Custom_SmartFormWrite.
const FUNCTION_NAME = 'ZAI_SMARTFORM_READ';
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
// dist/tools → project root
export const DEFAULT_SMARTFORM_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'output', 'smartforms');

const schema = z.object({
  name: z.string().min(1).max(30).describe('SmartForms name, e.g. LE_SHP_DELNOTE.'),
  outputDir: z.string().optional().describe('Folder where the XML is saved (default: output/smartforms in the project).'),
});

type Args = z.infer<typeof schema>;

export default defineTool({
  name: 'Custom_SmartFormRead',
  description:
    'Downloads any SmartForms (standard ones included) as XML and saves it locally; returns the file path. ' +
    'The file can be edited and uploaded again with Custom_SmartFormWrite. Changes nothing in SAP.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    const name = a.name.trim().toUpperCase();
    const res = await ctx.http.post(SOAP_RFC_PATH, buildEnvelope(FUNCTION_NAME, { IV_NAME: name }), 'text/xml; charset=utf-8', {
      SOAPAction: 'urn:sap-com:document:sap:rfc:functions',
      Accept: 'text/xml',
    });

    const fault = readFault(res.body);
    if (fault || res.statusCode !== 200) {
      return {
        isError: true,
        content: [{ type: 'text', text: `SOAP-RFC call failed (HTTP ${res.statusCode}): ${fault ?? res.body.slice(0, 2000)}` }],
      };
    }
    const error = readElement(res.body, 'EV_ERROR');
    if (error) return { isError: true, content: [{ type: 'text', text: error }] };

    let xml: Buffer;
    try {
      xml = decodeXml(readElement(res.body, 'EV_XML'));
    } catch (e) {
      return { isError: true, content: [{ type: 'text', text: (e as Error).message }] };
    }
    const path = await saveFile(a.outputDir ?? DEFAULT_SMARTFORM_DIR, xmlFileName(name), xml);
    return { content: [{ type: 'text', text: `XML saved: ${path}\nSize: ${xml.length} bytes` }] };
  },
});
