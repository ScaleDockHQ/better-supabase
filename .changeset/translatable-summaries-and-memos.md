---
"better-supabase": minor
---

Audit entries, ledger transactions and accounting entries that blocks write now keep a translation key and its raw values next to the English text (`summaryKey` and `summaryParams`, `memoKey` and `memoParams`), so an app can word them in its own locale. `BLOCK_MEMO_MESSAGES` lists every memo key with its English text. The English `summary` and `memo` are unchanged. The audit module moves to version 15 and the ledger module to version 3; run `better-supabase upgrade`.

`audit_event`, `audit_event_trusted` and `ledger_post` take two new trailing arguments, and the upgrade drops their old signatures. Calls by name or by position keep working. Only custom grants or comments on the old signatures, or views and functions that depend on them by signature, need attention: grant or comment again on the new signature.
