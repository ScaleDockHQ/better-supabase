---
"better-supabase": minor
---

`better-supabase/sql` exports a typed policy builder and a policy rule DSL:
`policy`, `renderPolicy`, `readPolicies`, `readGrants`, `maskSql`, `rulePolicy`,
`renderRulePolicy`, `readRulePolicies`, `renderRule`, `isRule`,
`disallowedPolicyCalls`, `policyFunctionsSql` and `POLICY_FUNCTIONS`, with the
`Policy` and `Rule` types. A rule renders to a policy that calls only
`bsb.is_member`, `bsb.can`, `bsb.owns` and `bsb.uid`, and reads back from the
`-- @bsb rule` comment above it.
