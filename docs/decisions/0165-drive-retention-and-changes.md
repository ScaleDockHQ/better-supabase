# 0165: Drive retention per label and a changes feed

- Status: accepted
- Date: 2026-10-31

## Context

Document management needs two things the drive lacked (ADR 0133 named the
second): files that expire by their label (contracts kept seven years,
drafts kept ninety days), and a way for a sync client to learn what changed
since its last call without listing the whole tree.

## Decision

- **Retention is a data lifecycle policy per label.** The kind is
  `drive_label_` plus the label name in lower case with runs of other
  characters as one underscore (`drive_retention_kind`). Policies, plans,
  floors and legal holds stay in ADR 0034's tables; drive adds no table.
- **`drive_retention_sweep` bins, it doesn't delete.** The service role call
  moves nodes whose last change is older than the shortest matching policy
  into the bin through `drive_trash`; the bin's own retention then purges
  them. Drive holds, legal holds on the kind and check-outs skip a node.
- **The feed is `updated_at` plus the id.** `drive_changes` returns nodes
  after a cursor `updated_at|id`, oldest first, and holds back the last five
  seconds so a late commit isn't skipped. A trigger touches `updated_at` when
  `deleted_at` changes, so a binned node comes back as `removed` and a
  restored one as a node.

## Alternatives considered

- **A change log table with tombstones.** It reports nodes deleted for good
  and access changes, but adds a table and a write per change to every
  adopter. Nodes reach the bin before purge, so the bin covers deletions.
- **A sequence as the cursor.** It orders by commit-independent numbers and
  can skip rows from transactions that commit late; the settle window on a
  timestamp is simpler and has the same gap risk, stated in the docs.
- **Retention names in config.** Tenants edit policies at run time; config
  would need a deploy per change.

## Consequences

The bin touch trigger changes `updated_at` on every trash and restore, which
also restarts a node's retention clock. The feed doesn't carry access
changes. A sweep that meets more locked nodes than its batch size at the
head of the queue binds on them again next time; raise `batchSize`. The
WOPI host (ADR 0166) reads the check-out lock, not this feed.
