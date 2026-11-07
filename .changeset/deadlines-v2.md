---
"better-supabase": minor
---

`deadlines` rule format v2: a rule set version is ordered groups of rules, a counting block and opaque `meta`, and each group yields one deadline per subject. See ADR 0242.

- `saveRules` takes `content` (`{ rules, groups, counting?, meta? }`) instead of `rules`, and `save_rule_version` takes the content as its third argument. Rules select subjects with `applies` (codes, `present`/`absent`, one date regime), carry `exceptions` and a deadline grammar: a count `from` or `before` a fact in days, business days or months, `day_of_month`, monthly `each: "furnishing_month"`, `first_of`, `earlier_of` and `later_of`. The counting block rolls a last day past weekends and the authored holidays.
- `compute` evaluates every group (or `group`) and returns the stored rows. A result is `due`, `unknown`, `pending`, `undated`, `not_covered`, `not_applicable`, `not_required` or `barred`, with `provisional`, `missing`, `exception`, `review`, `basis` and the rule's `deadline`. A group that requires a barred group falls with it.
- Facts are three-valued: a missing key is unknown, `null` does not exist or has not happened.
- `evaluateVersion` and `validateRuleVersion` replace `evaluateRule` and `validateRules`; `evaluate_deadlines` and `compute_deadlines` are the SQL functions. `evaluate_deadline_rule` and `compute_deadline` stay as deprecated wrappers until 0.58.
- `deadlines` rows gain `group_key`, `period`, `provisional`, `exception`, `review`, `basis`, `deadline` and `as_of`; `list` filters by `groupKey`, `period` and `provisional`. Events carry `groupKey`, `period` and `provisional`.

Run `better-supabase upgrade` and generate a migration. The upgrade converts stored version 1 rules (`anchor`, `offset`) to one group per rule and keeps an approved version's old hash in `meta.previous_content_hash`.
