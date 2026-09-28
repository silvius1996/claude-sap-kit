import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { defineTool, OperationType } from 'arc-1/public';
import { decodePdf, pdfFileName, savePdf } from '../pdf-file.js';
import { buildEnvelope, readElement, readFault } from '../soap-rfc.js';

// PDF preview of the print output of a NAST message (sales, deliveries, billing) through the FM
// ZAI_RUN_PRINT_PREVIEW: the print program runs to spool (no immediate printing),
// the spool stays in SP01 and is converted to PDF. The PDF is saved locally.
const FUNCTION_NAME = 'ZAI_RUN_PRINT_PREVIEW';
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';
// dist/tools → project root
const DEFAULT_OUTPUT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'output', 'print-preview');

const schema = z.object({
  document: z.string().min(1).max(30).describe('Document number (order, delivery or billing document), leading zeros optional.'),
  outputType: z.string().min(1).max(4).describe('NAST output type, e.g. BA00, LD00, RD00.'),
  application: z.enum(['V1', 'V2', 'V3']).optional().describe('NAST application: V1 sales, V2 deliveries, V3 billing.'),
  language: z.string().length(1).optional().describe('1-character SAP internal language (e.g. E, D) when there are several messages.'),
  partner: z.string().max(10).optional().describe('Message partner when there is more than one.'),
  device: z.string().min(1).max(4).optional().describe('Output device (default LP01, no immediate printing).'),
  outputDir: z.string().optional().describe('Folder where the PDF is saved (default: output/print-preview in the project).'),
  form: z.string().min(1).max(30).optional().describe('SmartForms to use instead of the configured one (requires program and routine).'),
  program: z.string().min(1).max(40).optional().describe('Print program to use with form, e.g. RLE_DELNOTE.'),
  routine: z.string().min(1).max(30).optional().describe('Print program routine to use with form, e.g. ENTRY.'),
});

type Args = z.infer<typeof schema>;

export default defineTool({
  name: 'Custom_PrintPreview',
  description:
    'Creates the PDF of the print output of an SD document (NAST message, print medium) by running the print program ' +
    'to spool and converting the spool to PDF; saves the file locally and returns its path. ' +
    'The spool stays in SP01. Does not create or change NAST messages. Does not cover S/4 Output Management (APOC). ' +
    'With form/program/routine it tries out a form that is not configured yet (TNAPR replaced in memory only).',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    const envelope = buildEnvelope(FUNCTION_NAME, {
      IV_DOCUMENT: a.document.trim(),
      IV_OUTPUT_TYPE: a.outputType.trim().toUpperCase(),
      IV_APPLICATION: a.application,
      IV_LANGUAGE: a.language?.toUpperCase(),
      IV_PARTNER: a.partner,
      IV_DEVICE: a.device?.toUpperCase(),
      IV_FORM: a.form?.trim().toUpperCase(),
      IV_PROGRAM: a.program?.trim().toUpperCase(),
      IV_ROUTINE: a.routine?.trim().toUpperCase(),
    });

    const res = await ctx.http.post(SOAP_RFC_PATH, envelope, 'text/xml; charset=utf-8', {
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
    if (error) {
      return { isError: true, content: [{ type: 'text', text: error }] };
    }

    let pdf: Buffer;
    try {
      pdf = decodePdf(readElement(res.body, 'EV_PDF'));
    } catch (e) {
      return { isError: true, content: [{ type: 'text', text: (e as Error).message }] };
    }

    const path = await savePdf(a.outputDir ?? DEFAULT_OUTPUT_DIR, pdfFileName(a.document, a.outputType), pdf);
    const lines = [
      `PDF saved: ${path}`,
      `Size: ${pdf.length} bytes`,
      `Program: ${readElement(res.body, 'EV_PROGRAM').trim()} / ${readElement(res.body, 'EV_ROUTINE').trim()}`,
      `Form: ${readElement(res.body, 'EV_FORM').trim() || '-'}`,
      `Spool requests (kept in SP01): ${readElement(res.body, 'EV_SPOOL_IDS').trim()} (${readElement(res.body, 'EV_SPOOL_TYPE').trim()})`,
    ];
    return { content: [{ type: 'text', text: lines.join('\n') }] };
  },
});
