---
"better-supabase": minor
---

The Rule builder UI recipe renders a rule editor with shadcn components: field, operator and value rows, nested And and Or groups, drag handles and a locked first condition. The `use-rule-editor` registry item installs `useRuleEditor`, which reads the organization from the session and the rules schema from `blocks.generated.ts`, and the preset catalog lists it.
