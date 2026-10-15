# Evaluations

Cases that check whether the skills make Claude do the right thing, and how much they add compared
with Claude without the plugin. They need no SAP system: the ARC-1 tools are not available in the
eval sandbox, so the cases check the plan and the tool calls Claude proposes.

```bash
claude plugin eval . --trust-plugin --runs 1
claude plugin eval . --trust-plugin --case smartform-copy-first
```

| Case | What it checks |
|---|---|
| `report-narrow-filters` | MB52 "for the whole stock" still gets a key selection (`WERKS` or `MATNR`) |
| `smartform-copy-first` | "Change the original directly" becomes a `ZAI_*` copy, and the original is replaced only with `prepare` + confirmation |
| `install-asks-first` | The installation starts by checking prefix, package and the `/sap/bc/soap/rfc` service |

Results go to `results/` (not in git). Add a case for every mistake found in real use.
