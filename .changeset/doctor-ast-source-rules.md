---
"better-supabase": patch
---

Read the TypeScript doctor source rules from the syntax tree. A comment or a string that mentions a call no longer counts, and findings, codes and lines stay the same for real code. BS260 reports only imported function and type names, and BS511 and BS621 count dynamic imports. BS210, BS219, BS227 and BS351 check receiver types when `typescript` 7.1 or newer is installed.
