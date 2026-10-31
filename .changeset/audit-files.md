---
"better-supabase": minor
---

New subpath `better-supabase/audit-files` reads and writes audit files for the general ledger. A
versioned `AuditFileAdapter` (`apiVersion: 1`) parses a file as a stream of ledger records and
exports books, with `saftAdapter()` for OECD SAF-T 2.00 and `xafAdapter()` for the Dutch XAF 3.2
(`SPEC_PINS.saftOecd`, `SPEC_PINS.xaf`). `importAuditFile(adapter, file, { run, imports })` writes
accounts, journals, opening balances and entries through the accounting import targets, so a repeat
changes nothing, and `exportAuditFile(adapter, accounting, { organizationId, company, currency,
selection })` writes a fiscal year. Parsing uses a small built-in streaming tokenizer with limits and
no XML dependency. Elements and links the ledger cannot store come back as warnings.
