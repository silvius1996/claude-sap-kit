import { z } from 'zod';
import { defineTool, OperationType } from 'arc-1/public';
import { buildEnvelope, readElement, readFault, readItems, type RsParam } from '../soap-rfc.js';

// Runs an executable report through the remote-enabled FM ZAI_RUN_REPORT, called via the
// standard service /sap/bc/soap/rfc. The FM does the SUBMIT with variant and/or selection values,
// without screen output, and returns the ALV data (JSON) or the classic list (text).
//
// The FM name is fixed: the tool is not a generic RFC gateway.
// Enabled by SAP_ALLOW_PLUGIN_RAW_WRITES=true + SAP_ALLOW_WRITES=true and scope 'write',
// because a report can also change data.
const FUNCTION_NAME = 'ZAI_RUN_REPORT';
const SOAP_RFC_PATH = '/sap/bc/soap/rfc';

const sapName = (max: number) =>
  z
    .string()
    .min(1)
    .max(max)
    .regex(/^(?:\/[A-Za-z0-9_]+\/)?[A-Za-z0-9_$]+$/u);

const paramSchema = z.object({
  name: z.string().min(1).max(8).describe('Name of the PARAMETER or SELECT-OPTIONS (e.g. MATNR, WERKS, P_DATUM).'),
  kind: z.enum(['P', 'S']).default('P').describe('P = parameter, S = select-option.'),
  sign: z.enum(['I', 'E']).default('I'),
  option: z.enum(['EQ', 'NE', 'BT', 'NB', 'GT', 'GE', 'LT', 'LE', 'CP', 'NP']).default('EQ'),
  low: z.string().max(45).default('').describe('Value in SAP internal format (dates YYYYMMDD, flag X).'),
  high: z.string().max(45).default(''),
});

const schema = z
  .object({
    report: sapName(40).optional().describe('Executable report to run, e.g. RM07MLBS.'),
    tcode: sapName(20).optional().describe('Instead of report: a report transaction, e.g. MB52.'),
    variant: z.string().min(1).max(14).optional().describe('Variant saved in the logged-on client.'),
    params: z
      .array(paramSchema)
      .max(500)
      .default([])
      .describe('Selection values; they override the variant values. Several rows for the same select-option.'),
    maxRows: z.number().int().min(1).max(5000).default(200).describe('Maximum rows returned.'),
  })
  .refine((a) => a.report || a.tcode, { message: 'Specify report or tcode' });

type Args = z.infer<typeof schema>;

export default defineTool({
  name: 'Custom_LaunchReport',
  description:
    'Runs an executable SAP report (by name or transaction) with a variant and/or selection values, ' +
    'without SAP GUI, and returns the ALV data as JSON or the classic list as text. ' +
    'Does not work with dialog transactions or reports that open popups or screens. ' +
    'Requires the FM ZAI_RUN_REPORT and the active SICF service /sap/bc/soap/rfc.',
  schema,
  policy: { scope: 'write', opType: OperationType.Workflow },
  availableOn: 'onprem',
  async handler(args, ctx) {
    const a = args as Args;
    const rsparams: RsParam[] = a.params.map((p) => ({
      SELNAME: p.name.toUpperCase(),
      KIND: p.kind,
      SIGN: p.sign,
      OPTION: p.option,
      LOW: p.low,
      HIGH: p.high,
    }));

    const envelope = buildEnvelope(FUNCTION_NAME, {
      IV_REPORT: a.report?.toUpperCase(),
      IV_TCODE: a.tcode?.toUpperCase(),
      IV_VARIANT: a.variant,
      IT_PARAMS: rsparams.length > 0 ? rsparams : undefined,
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

    const report = readElement(res.body, 'EV_REPORT').trim();
    const variant = readElement(res.body, 'EV_VARIANT').trim();
    const outputType = readElement(res.body, 'EV_OUTPUT_TYPE').trim();
    const header = `Report ${report}${variant ? ` - variant ${variant}` : ''} - output ${outputType}`;

    if (outputType === 'ALV') {
      const rows = JSON.parse(readElement(res.body, 'EV_DATA_JSON') || '[]') as unknown[];
      const shown = rows.slice(0, a.maxRows);
      const note = rows.length > shown.length ? ` (showing the first ${shown.length})` : '';
      return {
        content: [{ type: 'text', text: `${header}\nRows: ${rows.length}${note}\n${JSON.stringify(shown, null, 1)}` }],
      };
    }

    if (outputType === 'LIST') {
      const lines = readItems(res.body, 'ET_LIST');
      const shown = lines.slice(0, a.maxRows);
      const note = lines.length > shown.length ? ` (showing the first ${shown.length})` : '';
      return { content: [{ type: 'text', text: `${header}\nRows: ${lines.length}${note}\n${shown.join('\n')}` }] };
    }

    return { content: [{ type: 'text', text: `${header}\nThe report produced no output (no ALV and no list).` }] };
  },
});
