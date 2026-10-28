# 0119: Tenant approval policies tighten config floors; approvals are consumed once

- Status: accepted
- Date: 2026-10-28

## Context

Approval policies were fixed per subject type and action in
`blocks.approvals.options.policies`. An organization could not require a
second approver for large refunds, ask for a requester's manager, or turn
approvals on for an action the platform leaves open. Apps that wanted this
either forked the policy into their own table or filed requests through a
rule action per chain (ADR 0046), which gave no single answer to "does this
request need an approval, and which".

Two other gaps came from the same adopters. Some actions need a deliberate
second look by the requester, not another person's consent. And
`is_approved(subject, action)` answers whether a subject was approved, which
suits a status change but not an operation such as a refund or an export:
the same approval could run the operation twice, or run a different
operation than the one that was approved.

## Decision

`options.tenantPolicies: true` adds an `approval_policies` table per tenant,
tenant-scoped through `bsb_tenant_scope` and adoptable like every block table
(ADR 0098). A tenant policy names a subject type and action that the config
already declares; the config policy is the platform floor and a tenant can
only tighten it. `approval_effective_policy` merges the floor with every
enabled tenant policy whose `conditions` match the request payload, in
creation order: steps are appended, the strictest mode wins, `selfApproval`
holds only when every policy allows it, and the shortest expiry wins.
Conditions are rules filter trees evaluated with `rule_matches` from the
automations block, so the tree format and its checks are the same as for
rules. A floor with no steps asks for nothing until a tenant policy adds a
step or a mode; without tenant policies a floor needs one.

A policy has a `mode`: `authorize` (the default, someone else decides) or
`confirm` (the requester may approve their own request, and that approval
finishes it). Merge order is nothing, then confirm, then authorize.
`approvers.manager: true` resolves the requester's manager through the
employees block, while the manager is an active member and not offboarded.

`consume_approval(id, fingerprint)` marks an approved request `consumed_at`
once, and refuses a second call or a fingerprint other than the one stored at
request time. The fingerprint is a lowercase hex SHA-256 of the operation;
`approvalFingerprint` builds it from sorted-key JSON. `approval_requirement`
returns the merged policy for a payload, or null when nothing is required,
and `request_approval` refuses a request nothing requires.

Policies are managed with `approvals.manage` and read with `approvals.read`;
no new permission keys.

## Alternatives considered

- Tenant policies that replace the config policy. Rejected: a tenant could
  remove a control the platform relies on, such as the finance step on
  refunds.
- A separate condition language for policies. Rejected: rules filter trees
  already have a UI, a checker and a SQL evaluator.
- RFC 8785 JSON canonicalization for fingerprints. Rejected for now: sorted
  keys with `JSON.stringify` values cover the operations apps fingerprint
  (ids, amounts, currency codes), and the SQL side only compares the hash.
- Reusing `is_approved` with a "used" flag per subject and action. Rejected:
  it can't tell two operations on the same subject apart.

## Consequences

`request_approval` gains a `fingerprint` argument, so apps that call it
directly in custom mode pass one more (optional) argument. Policies with a
manager approver need the employees block; conditions need the automations
block. Revisit the merge rules if tenants need to loosen a floor for a
segment, which would need an explicit platform opt-in per policy.
