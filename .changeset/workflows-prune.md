---
"better-supabase": minor
---

`better-supabase db prune-workflows` is `better-supabase workflows prune`, in a `workflows` group with its own docs page. The flags are unchanged and the old command has no alias, so change the cron entries and scripts that run it.

| Old                                  | New                               |
| ------------------------------------ | --------------------------------- |
| `better-supabase db prune-workflows` | `better-supabase workflows prune` |
