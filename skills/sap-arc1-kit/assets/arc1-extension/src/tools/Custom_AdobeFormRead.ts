import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { defineTool, OperationType, type ToolContext } from 'arc-1/public';
import { decodeFormXml, decodeLayout, findInterfaceName, formFileNames, interfaceFileName } from '../adobe-form-file.js';
import { savePdf as saveFile } from '../pdf-file.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';

// Downloads an Adobe form into output/adobe-forms: the form as XML without layout, the layout as XDP
// and the form interface as XML, to read them or edit them locally before Custom_AdobeFormWrite.
const FUNCTION_NAME = 'ZAI_ADOBE_FORM_READ';
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
const HEADERS = { SOAPAction: 'urn:sap-com:document:sap:rfc:functions', Accept: 'text/xml' };
// dist/tools → project root
export const DEFAULT_ADOBE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'output', 'adobe-forms');

const schema = z.object({
  name: z.string().min(1).max(30).describe('Adobe form name (transaction SFP), e.g. FP_TEST_00.'),
  interface: z
    .string()
    .min(1)
    .max(30)
    .optional()
    .describe('Form interface to download as well (default: the one named in the form XML, when found).'),
  outputDir: z.string().optional().describe('Folder where the files are saved (default: output/adobe-forms in the project).'),
});

type Args = z.infer<typeof schema>;

export async function callAdobeRead(ctx: ToolContext, params: Record<string, string | undefined>): Promise<string> {
  const res = await ctx.http.post(SOAP_RFC_PATH, buildEnvelope(FUNCTION_NAME, params), 'text/xml; charset=utf-8', HEADERS);
  const fault = readFault(res.body);
  if (fault || res.statusCode !== 200) {
    throw new Error(`SOAP-RFC call failed (HTTP ${res.statusCode}): ${fault ?? res.body.slice(0, 2000)}`);
  }
  return res.body;
}

export default defineTool({
  name: 'Custom_AdobeFormRead',
  description:
    'Downloads any Adobe form (SFP, standard ones included) and saves three files locally: the form as XML ' +
    'without layout (context, properties), the layout as XDP and the form interface as XML. Returns the paths. ' +
    'Form and layout can be edited and uploaded again with Custom_AdobeFormWrite, the interface with ' +
    'Custom_AdobeInterfaceWrite. Changes nothing in SAP.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    const name = a.name.trim().toUpperCase();
    const dir = a.outputDir ?? DEFAULT_ADOBE_DIR;
    try {
      const body = await callAdobeRead(ctx, { IV_NAME: name, IV_INTERFACE: a.interface?.trim().toUpperCase() });
      const error = readElement(body, 'EV_ERROR');
      if (error) return { isError: true, content: [{ type: 'text', text: error }] };

      const form = decodeFormXml(readElement(body, 'EV_FORM'));
      const layout = decodeLayout(readElement(body, 'EV_LAYOUT'));
      const files = formFileNames(name);
      const lines = [
        `Form XML (without layout): ${await saveFile(dir, files.form, form)}`,
        `Layout XDP: ${await saveFile(dir, files.layout, layout)}`,
      ];

      // Interface: the one asked for, otherwise the one named in the form XML
      const interfaceName = a.interface?.trim().toUpperCase() ?? findInterfaceName(form);
      if (!interfaceName) {
        lines.push('Interface: name not found in the form XML; pass it with "interface" to download it');
      } else {
        const interfaceBody = a.interface ? body : await callAdobeRead(ctx, { IV_INTERFACE: interfaceName });
        const interfaceError = readElement(interfaceBody, 'EV_ERROR');
        lines.push(
          interfaceError
            ? `Interface ${interfaceName} not downloaded: ${interfaceError}`
            : `Interface ${interfaceName}: ${await saveFile(dir, interfaceFileName(interfaceName), decodeFormXml(readElement(interfaceBody, 'EV_INTERFACE')))}`,
        );
      }
      return { content: [{ type: 'text', text: lines.join('\n') }] };
    } catch (e) {
      return { isError: true, content: [{ type: 'text', text: (e as Error).message }] };
    }
  },
});
