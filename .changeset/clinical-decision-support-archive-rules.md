---
"better-supabase": minor
---

Breaking: `clinicalDecisionSupport` gets `archiveRule` and `restoreRule`, and the
hard delete of a rule is `purge`, behind its own `permissions.purge` key (it
falls back to `clinical_decision_support.manage`). An archived rule leaves
`rules` and the evaluation, and `saveRule` refuses it with
`DECISION_SUPPORT_RULE_ARCHIVED`; alerts it raised stay until the next
evaluation resolves them. `rules` takes `includeArchived`, and `CareRule`
carries `archivedAt`.

| Before                               | After                                 |
| ------------------------------------ | ------------------------------------- |
| `clinicalDecisionSupport.deleteRule` | `clinicalDecisionSupport.purgeRule`   |
| `delete_care_rule(rule_id)`          | `purge_care_rule(rule_id)`            |
| event `care_rule.deleted`            | event `care_rule.purged`              |
| `list_care_rules` with one argument  | a second argument, `include_archived` |

New events are `care_rule.archived` and `care_rule.restored`. Run
`better-supabase upgrade` and apply the migration. See the 0.66 to 0.67 guide.
