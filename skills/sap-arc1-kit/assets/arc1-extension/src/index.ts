import type { Plugin } from 'arc-1/public';
import launchReport from './tools/Custom_LaunchReport.js';
import printPreview from './tools/Custom_PrintPreview.js';
import smartFormRead from './tools/Custom_SmartFormRead.js';
import smartFormWrite from './tools/Custom_SmartFormWrite.js';
import smartFormReplace from './tools/Custom_SmartFormReplace.js';
import adobeFormRead from './tools/Custom_AdobeFormRead.js';
import adobeFormWrite from './tools/Custom_AdobeFormWrite.js';
import adobeInterfaceWrite from './tools/Custom_AdobeInterfaceWrite.js';

// Loaded by ARC-1 with:
//   ARC1_PLUGINS=<absolute path>/arc1-extension/dist/index.js
const plugin: Plugin = {
  name: 'arc1-sap-tools',
  version: '0.6.0',
  apiVersion: 1,
  tools: [
    launchReport,
    printPreview,
    smartFormRead,
    smartFormWrite,
    smartFormReplace,
    adobeFormRead,
    adobeFormWrite,
    adobeInterfaceWrite,
  ],
};

export default plugin;
