# 0093: Install blocks as named instances behind one data contract

- Status: accepted
- Date: 2026-10-22

## Context

A developer picks blocks in Create, the CLI or the config and expects a
working product: a ChatGPT clone, a CRM, a CMS, an ERP or a PIM out of the
same catalog. Today that pick is not enough.

- Using the data takes plumbing. Block clients take a `transport` and a
  `tenant`, and the Next.js example hand-writes a 230-line `lib/blocks.ts`.
  Block methods differ per block for the same job (`save`, `create`, `set`,
  `apply`), take positional arguments and return booleans from `update`.
  App tables use a second vocabulary (`findMany`, `findFirst`, `findUnique`,
  `paginate`, `createMany`). Only 30 of 136 blocks have hooks, and those are
  widget hooks.
- The same concept exists twice: the `tenant`, `actor`, `timestamps` and
  `soft-delete` plugins next to the `tenant`, `actor`, `updated-at` and
  `trash` blocks; sections (ADR 0064) that wrap one block each; three UI
  paths (`scaffold screens`, generated features, recipes); four API layers
  and five spec subpaths; a split automation stack; seven client data
  layers; and several places the organization comes from.
- The surface is large: 337 subpaths (120 of them per-framework block
  folders), about 40 flat config keys and 26 CLI commands, several of which
  overlap.
- Names drift: "SQL module" for a block, "feature" for four things, jargon
  block names (parties, engagements, work-items), clashes (the `jobs` block
  and the hiring `jobs` table) and append-only preset code tables that need a
  new entry for every rename.
- A block installs once. Everything is keyed by the block name, and the
  generic blocks (approvals, subjects, pipelines, share-links, bulk) name
  their consumers in SQL.

## Decision

**One term per concept.** The glossary on the docs Naming page is the
source of truth. A block is the unit you install, and an instance is one
named install of it. A record type replaces subject, names replace
entities, `tables` replace `appTables`, and a design is the only preset
format. "Organization" is the user-facing word for the account that owns
data; `tenant` stays in internal code. The client is called `bsb`
everywhere: the app variable, the CLI, markers, query keys, headers and
database object prefixes.

**Plain default names that every app can rename.** Jargon blocks get plain
names (work-items become `tasks`, parties become `contacts`, engagements
become `activities`, number-sequences become `numbering`), clashes are
fixed (jobs becomes `queue`, rules becomes `automations`, tenant becomes
`memberships`), and every block declares `names` so presets can rename its
nouns per vertical (tasks become tickets in a helpdesk).

A block rename changes the block name, its subpath, its exports, its
operation prefix and its CloudEvent source. Table names, permission keys,
event types, hint codes and queue names keep their 0.14 values, so an
installed database moves only its `better_supabase.blocks` rows. Two tables
clashed with a renamed block and move: hiring's `jobs` becomes
`job_openings` and catalog's `collections` becomes `product_collections`.

**Instances.** `blocks` in the config is keyed by instance. An entry takes
`block` (defaulting to the key), `on` (the record types an attachable block
attaches to, defaulting to all of them) and `uses` (which instance of a
dependency to bind). Each instance gets its own tables, named from the
instance. Core blocks (memberships, permissions, record types, outbox,
queue, audit) are singletons. Generic blocks stop naming their consumers:
consumers register through `contributes`.

**One data contract for app tables and block tables.** Reads are `list`,
`page`, `get`, `count` and `aggregate`; writes are `create`, `update`,
`upsert` and `delete`, taking objects or arrays and returning the rows they
wrote; `attach` and `detach` link a row to a record. Domain verbs
(`approve`, `send`, `publish`) stay, each with one object input. The
repository's `find*` and `*Many` methods fold into these verbs. Results stay
`Result` values (invariant 4).

**The client and generated hooks.** App code never passes a transport, and
passes the organization only to override it. `bsb.db()` on the server and
`ctx.db` in actions expose every instance and table. `gen` writes one hook
per instance and table (`useTickets`, `useCustomers`), running on TanStack
Query when the app installs it and on the library's controllers otherwise.
PowerSync, TanStack DB and SQLite become engines behind the same hooks.

**Removed layers.** Built-in plugins become block extensions (the
`plugins` key goes; `definePlugin` stays as the versioned third-party
interface). Sections, record features and `sectionAction` go, replaced by
one generated `records/<type>.ts` per record type (this supersedes ADR 0064).
The per-framework block folders go; widget logic stays as headless
controllers and the wrappers become registry items, which are the only UI
path. `defineApi` includes every instance and table, oRPC becomes its
implementation, and the specs live under `better-supabase/spec`. Flows
become default automations with one trigger (the outbox event), one action
registry (ADR 0046) and one scheduler on the queue. Preset codes give way
to the design JSON (ADR 0040, ADR 0058): the config's `preset` takes a name
or an object with the conventions that differ and the blocks, a design
carries it in its own `preset` key (format 7), a design file is that JSON,
and `codemod 0.15` converts a 0.14 code with a frozen copy of its decoder. The config groups into `database`,
`auth`, `records`, `tables`, `blocks`, `adapters`, `gen`, `api` and
`tooling`, with one organization resolver at `auth.organization`. The CLI
keeps one command per job and gains `remove`.

Temporal stays in the public API (ADR 0005).

This amends ADRs 0012, 0029, 0030, 0031, 0040, 0046, 0058, 0060 and 0061,
and supersedes ADR 0064. The work ships in phases, one pull request each,
listed on the roadmap; every phase ships a codemod or a doctor lint for what
it removes.

## Alternatives considered

- **Merge blocks into a few generic kinds** (one "items" table for tasks,
  tickets and deals). Rejected: blocks carry specific fields and relations,
  and a generic table loses the constraints, indexes and RLS that make them
  safe. Instances give the reuse without the merge.
- **Keep sections and add instances on top.** Rejected: sections are
  one-line wrappers for 20 of 21 blocks, and a second key space doubles the
  staleness rules. A generated record file covers the same need.
- **Keep the repository API and add the block verbs next to it.** Rejected:
  two vocabularies for the same job is the problem this decision removes.
- **Ship the changes in one release.** Rejected: the diff would be
  unreviewable. Phases land renames and removals first, so later phases
  build on the new names.

## Consequences

Picking blocks builds a product: instances, attachments and wiring come
from the config, and `useTickets()` works like `useCustomers()`. The export
map shrinks from about 337 subpaths to about 130, and the docs describe one
way to read data, one way to install UI and one automation model.

Nearly every app call site, permission key and event type changes. Adopters
run one codemod per phase, and doctor lints flag what the codemod can't
rewrite. Database object renames (`bs_*` to `bsb_*`, block renames) run
through `upgrade`, so installed projects need a migration per breaking
phase. Engines with different cache and sync semantics have to pass one
contract suite. We would revisit instances if a block can't keep its
constraints when installed twice, and the engines if one can't meet the
contract.
