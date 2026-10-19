---
"better-supabase": minor
---

The rules block has an editor controller. `useRuleBuilder` from `better-supabase/blocks/rules/react` (and `/vue`, `/svelte`, `/solid`) loads a subject type's fields and a rule, edits its condition tree, reports the problems `checkRuleConditions` finds and whether anything changed, and saves the rule with its version. Nodes named in `locked` can't be changed, moved or removed. `createRuleBuilderController` is the same state without a framework, and the tree helpers it uses (`findNode`, `insertNode`, `moveNode`, `removeNode`, `setRuleField`, `setRuleOperator` and others) are exported from `better-supabase/blocks/rules`.
