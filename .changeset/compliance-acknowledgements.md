---
"better-supabase": minor
---

Compliance policy acknowledgements move onto the acknowledgements block (ADR 0131). `blocks.compliance` now requires `acknowledgements`, contributes the `compliance_policy` record type with its current version, and assigns a policy that requires acknowledgement to the `member` role when it is saved. The [0.46 to 0.47 guide](https://bettersupabase.com/docs/migration/0.46-to-0.47#policy-acknowledgements) lists every change.

| Before (0.46)                                   | After (0.47)                                                 |
| ----------------------------------------------- | ------------------------------------------------------------ |
| `acknowledge_compliance_policy(policy_id)`      | `acknowledge('compliance_policy', policy_id::text)`          |
| `list_compliance_policies(..., pending_only)`   | `list_my_acknowledgements(tenant)`                           |
| `compliance_policy_acknowledgements(policy_id)` | `acknowledgement_status`, `acknowledgements_of`              |
| `policy_acknowledgements` table                 | `acknowledgements` rows of type `compliance_policy`          |
| `compliance.acknowledge` permission             | `acknowledgements.acknowledge`                               |
| `policy.acknowledged` event                     | `acknowledgement.created`                                    |
| `COMPLIANCE_POLICY_NOT_PUBLISHED` hint          | `ACKNOWLEDGEMENT_NO_VERSION`, `ACKNOWLEDGEMENT_NOT_ASSIGNED` |

- `upgrade` renders a data step that copies the stored acknowledgements, assigns the live policies to the `member` role and drops `policy_acknowledgements`.
- `PERMISSION_KEY_RENAMES` and `EVENT_TYPE_RENAMES` map the old permission and event; `codemod 0.47` lists the old calls for review.
- The compliance client keeps `acknowledgePolicy`, `acknowledgements(policyId)` and the `pendingOnly` option as deprecated wrappers over the acknowledgements functions until 0.48.
