---
"better-supabase": minor
---

Three core hint codes carry the noun they belong to, and the policy helper functions live in `better_supabase`. `better-supabase codemod naming` renames the hints in your code and writes a hand migration that moves the helper functions.

| Old                   | New                               |
| --------------------- | --------------------------------- |
| `CHAIN_SIGNER`        | `AUDIT_CHAIN_SIGNER`              |
| `APPEND_ONLY`         | `TABLE_APPEND_ONLY`               |
| `FISCAL_YEAR_CLOSED`  | `PERIOD_CLOSED`                   |
| `bsb.uid()`           | `better_supabase.uid()`           |
| `bsb.owns(uuid)`      | `better_supabase.owns(uuid)`      |
| `bsb.is_member(uuid)` | `better_supabase.is_member(uuid)` |
| `bsb.can(uuid, text)` | `better_supabase.can(uuid, text)` |

The naming table gains the `hint`, `event` and `sqlFunction` kinds, and doctor BS260 reports a source file that still compares against an old hint code.
