# 0587: Record the status of the ADR 0393 and 0420 leftovers

## Status

Accepted. Amends ADR 0393 and 0420.

## Context

ADR 0393 listed what the declarative base layer release left for later, and ADR 0420 listed offline and PowerSync work. Several items have shipped since, and a reader of 0393 cannot tell which.

## Decision

| Leftover                                                          | Status                                                                    | Where          |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------- | -------------- |
| Owned-column default flip                                         | Done                                                                      | ADR 0580       |
| PowerSync streams for child tables                                | Done                                                                      | ADR 0420       |
| Notifications and settings inference                              | Done                                                                      | ADR 0394       |
| Reading through views                                             | Decided against for block clients, shipped for typed reads and cache tags | ADR 0471, 0586 |
| Drive `grants` mode                                               | Deferred, with its reason                                                 | ADR 0586       |
| Generated file layout (`schema.ts`, `tables/`, `blocks/index.ts`) | Open, owned by the client and server split work                           | Track A        |
| Approval item columns                                             | Done                                                                      | ADR 0585       |
| Tenantless notifications and audit                                | Deferred, with its reason                                                 | ADR 0588       |
| The cloud app's `/create` `integrations` field                    | Outside this repository                                                   | ADR 0393       |

## Consequences

ADR 0393's deferred list is read through this table. A later change that closes an item adds a row here.
