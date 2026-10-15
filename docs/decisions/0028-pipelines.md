# 0028: Run record stages on tenant-editable pipelines, separate from status

- Status: accepted
- Date: 2026-10-14

## Context

Deals, quotes, invoices, orders, job applications, tickets and work items
all move through stages, and an organization names and orders those stages
itself: HubSpot, Pipedrive and Salesforce keep several pipelines per
organization, Linear and Jira let each team define its workflow states, and
CentraKit hand-builds the same thing twice (`hiring_stages` and
`workflow_lifecycles`). The `state-machine` module can't serve: its states
and edges are config compiled into one trigger per subject type, and its
history stores the status text, so a renamed state loses its past.

Behind every product's configurable stages sits a short fixed list:
Linear's workflow state types, Jira's status categories, Salesforce's
`IsClosed` and `IsWon`, Pipedrive's open, won and lost. Reports read that
list, not the stage names.

## Decision

The `pipelines` module (`src/sql/modules/pipelines.ts`) keeps pipelines and
stages as tenant rows for every subject type bound in
`options.subjects`. Each binding declares its categories, and each category
maps to one fixed outcome: `open`, `success` or `failure`. A stage stores
its category and the outcome it implies, so a stage holding records never
changes outcome. A trigger per bound table checks the stage, stamps the
time it was entered, closes and opens `pipeline_stage_history` rows with
the stage name as it was, and records `pipeline.stage_changed` with the
record as its subject.

Stage and status stay two columns. The stage is the organization's
pipeline, which people move; the status is the system lifecycle, which
events move and `state-machine` or the module guards. A binding's `status`
maps categories to status values, and an after trigger writes the status in
its own update, so a state machine on the status column still checks the
change. The status never sets the stage.

## Alternatives considered

- **Tenant-editable states inside state-machine.** Its edge checks are
  `case` literals compiled per machine, there is one machine per subject
  type (no pipeline per job), and its history keys on status text. Moving
  it to runtime lookups would change every existing machine.
- **An enum or text stage column.** A rename would rewrite every record and
  every history row, and two pipelines of one type couldn't share a key.
- **Outcome as free text per stage.** Reports would need a mapping per
  organization; the fixed three keep `winRate` and "is it open" one rule.

## Consequences

Record blocks (deals, work items, quotes, hiring) bind to `pipelines`
instead of each shipping stage tables, and a board, stats and health read
come with every binding. Board moves go through `rank.move` with the stage
id as the group, which needed `move()` to cast the group to the column's
type. A pipeline per scope covers hiring's pipeline per job. Revisit if an
app needs a stage outcome beyond the three, such as a neutral "parked".
