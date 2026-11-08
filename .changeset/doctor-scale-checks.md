---
"better-supabase": minor
---

`better-supabase doctor` checks scale practices. BS386 flags a volatile or PL/pgSQL function called per row in a policy, BS387 a table with six or more row-level `bsb_*` triggers, BS388 a search trigger on an import target without the import guard, BS389 an audit log nothing purges, BS390 a redundant index, BS391 a `param is null or col = any(param)` filter in a function, and BS392 a searched table without a trigram or time index. BS227 also reports `count()` without a `mode`. `better-supabase upgrade` rewrites no module and no data moves.
