// Rows of a report output (ALV rows or list lines) with the note on how many are shown.
// ZAI_RUN_REPORT already returns only the first maxRows rows and the full number in EV_ROW_COUNT;
// the cut is repeated here for tables the FM cannot shorten (hashed) and for an older FM without the limit.

export function formatRows<T>(rows: T[], total: number, maxRows: number): { shown: T[]; summary: string } {
  const shown = rows.slice(0, maxRows);
  const count = Number.isInteger(total) && total >= rows.length ? total : rows.length;
  const note = count > shown.length ? ` (showing the first ${shown.length})` : '';
  return { shown, summary: `Rows: ${count}${note}` };
}
