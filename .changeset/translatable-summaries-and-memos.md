---
"better-supabase": minor
---

Audit entries, ledger transactions and accounting entries that blocks write now keep a translation key and its raw values next to the English text (`summaryKey` and `summaryParams`, `memoKey` and `memoParams`), so an app can word them in its own locale. `BLOCK_MEMO_MESSAGES` lists every memo key with its English text. The English `summary` and `memo` are unchanged. The audit module moves to version 15 and the ledger module to version 3; run `better-supabase upgrade`.
