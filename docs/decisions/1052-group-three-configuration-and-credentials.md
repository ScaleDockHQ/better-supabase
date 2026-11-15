# 1052: Group three, configuration and credentials (lane Y2, slice 6)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts configuration and credential tables last and says each is decided
one at a time from its read paths: the lifecycle verb there is revoke or
disable, and a delete is a purge. This slice reads the delete function of each
of them. The question for every row is the same: does a delete lose a record
that people entered or an outside party relies on, or does it remove a setting
that a state already switches off and that the owner can recreate?

## Decision

Sixteen entities keep their delete and get no archive. In every case a state or
the delete itself already does the job an archive would do, and for a
credential an archive would be wrong: a hidden secret that a restore brings back
is a secret nobody decided to reactivate.

| Entity                     | Block                | Why delete is the verb                                                                                        |
| -------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------- |
| `flag`                     | `flags`              | `enabled` and the `archived` state already switch a flag off, and `delete_flag` is the purge of its overrides |
| `automation`               | `automations`        | `enabled` switches a rule off, a block-shipped rule cannot be removed, and removal needs the admin key        |
| `segment`                  | `segments`           | A saved filter whose members are derived; recreating it restores the same members                             |
| `tag`                      | `tags`               | A label: removing it drops the links, and the tagged records keep their own state                             |
| `approval_policy`          | `approvals`          | `enabled` switches a policy off, and no table references a policy, so a delete loses a rule and no decision   |
| `connector`                | `connectors`         | `delete_connector_server` returns the live grants so the caller revokes each one at its provider              |
| `credential`               | `credentials`        | The row's trigger drops the Vault secret; a restore could not bring the secret back                           |
| `ai_provider_key`          | `ai-keys`            | Same as a credential: the delete drops the secret, and a new key is a new decision                            |
| `oauth_client`             | `oauth-server`       | `delete_oauth_client` removes the grants and codes, so every issued token fails the grant check               |
| `incoming_webhook`         | `webhooks`           | The endpoint's secret goes with the row; `webhook_endpoint.disabled` is the reversible state                  |
| `hostname`                 | `domains`            | `resolve_hostname` stops answering at once; adding the name again needs a new DNS verification                |
| `ssf_stream`               | `security-events`    | Delivery config: the delete drops the stream, its held SETs and its endpoint, and a new stream starts clean   |
| `sso_domain`               | `sso`                | Ownership of a domain is proven again by DNS, so a restored row would claim a name nobody verified            |
| `scim_user`, `scim_group`  | `sso`                | The identity provider drives them, and its next sync recreates a row that should exist                        |
| `marketplace_installation` | `vercel-marketplace` | The vendor's uninstall ends it, and the vendor owns the record                                                |

An archived credential, hostname or OAuth client would stay a row that a
restore can turn back on, so none of them gets one. Revoke semantics already
exist and are tested: the Vault secret is dropped, the live connector grants
are returned for revocation, the OAuth grants are deleted, and
`resolve_hostname` returns nothing for a removed name.

Seven entities hold records that a delete destroys with their dependents, so
each gets an archive, a restore and a purge in its own slice, with its own ADR
number, migration and pgTAP test:

| Entity               | Block                       | What a delete loses today                               |
| -------------------- | --------------------------- | ------------------------------------------------------- |
| `field_definition`   | `custom-fields`             | Every stored value of the field on every record         |
| `enrollment_program` | `enrollments`               | Every enrollment and the steps each person completed    |
| `sequence`           | `sequences`                 | Every enrollment and its progress                       |
| `score_model`        | `scores`                    | The model's versions and every score computed with them |
| `drive`              | `drive`                     | The drive's folders, files, grants and shares           |
| `care_rule`          | `clinical-decision-support` | The rule that raised alerts that stay in the chart      |
| `agent`              | `agents`                    | The agent's conversations, runs and skills              |

## Consequences

ADR 1041's table lists the sixteen. EX-1207 counts them as decided and the seven
stay open until their slices merge. The slices rename the delete method to
`purge`, so each lists old and new names in its changeset and the 0.66 to 0.67
migration guide.
