---
"better-supabase": minor
---

A state machine with an app history table writes the actor columns the table declares as `actor_name`, `actor_email`, `ip` and `user_agent` without naming them in `history`, and a child of a rows template in `blocks.templates.options.types` needs no `parent` when the schema declares one foreign key from the child to the root table. An entry in the config still wins, and `better-supabase codemod config --prune` removes the ones the schema now makes redundant. See ADR 1190.
