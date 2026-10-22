# 0064: Compose blocks through sections, flows and three layers

- Status: superseded by 0093
- Date: 2026-10-22

## Context

An app that installs several blocks needs them to work together: a record
page shows comments, files and versions next to the row, a list shows a
comment count per row, an inbox conversation turns into a work item, and a
create form shows the tenant's custom fields next to the entity's own. Each
of these crosses block boundaries. Without a rule for where that glue lives,
it ends up in three places at once: in the library as one-off helpers per
pair of blocks, in generated code that apps can't change, and in copied UI
that drifts from both.

## Decision

Blocks compose through three layers, each with one owner.

1. Library logic. `better-supabase/records` holds record sections, record
   lists, the timeline, `loadMyWork` and `entityForm`.
   `better-supabase/flows` holds `defineFlow`, `createFlows` and the
   built-in flows. These take block clients and entity schemas as inputs and
   never import a block's runtime, so a block that isn't installed costs
   nothing.
2. One regenerated binding per subject. `gen` with `generateFeatures` writes
   one feature file per subject that names its sections, plus navigation and
   commands. The app never edits these files; `gen` writes them again when
   the config changes.
3. UI from recipes only. Screens and components ship as recipes over the
   app's shadcn components (ADR 0031), such as the record list, the subject
   timeline, My work and the entity form. The library ships headless hooks
   (`useRecordListState`, `useEntityForm`) and no markup.

A section is the unit that crosses layers: a named part of one record with a
`load`, an optional `count` and a permission, settled on its own as `ok`,
`error` or `hidden`. Pages, list columns and the timeline all read sections.

A flow is the unit that crosses blocks on writes: a trigger event, a source,
a typed mapping and a target block. It runs once per source record through
the outbox and, when given an `enqueue`, through jobs, and it records the
lineage as a `created_from` relation, which is also how it finds an earlier
run. A built-in flow runs only when the app lists it in `createFlows`.
Flows carry `apiVersion: 1`.

## Alternatives considered

Generating the flows and forms from the config. That puts app decisions
(which conversation becomes a work item, which fields a form shows) into
files the app can't edit, and every change waits on a `gen` release.

A config key that turns built-in flows on. A flow needs block clients for the
tenant and, for `quoteToOrder`, an app-supplied `create`, which a config file
can't hold. Listing flows in `createFlows` keeps that code next to the
consumer.

Shipping form and list components from the library. They would fix one
markup and one design system on every app, which ADR 0031 already rejected
for blocks.

## Consequences

A new cross-block feature lands as a section, a flow or a recipe, and the
docs page "Composing blocks" names which. Generated bindings stay thin, so
`gen` changes rarely break apps. The cost is that an app wires flows and
recipes by hand. Orders have no conversion from a quote yet, so
`quoteToOrder` needs the app's `create`; an `orders.fromQuote` function
would remove that.
