"use client";

import type { ReactElement } from "react";

import { presetBlockConflict, resolvePreset } from "better-supabase/preset";
import { LayersIcon } from "lucide-react";
import { useId, useMemo } from "react";

import type { SchemaTable } from "@/lib/schema";

import { Badge } from "@/components/reui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Switch } from "@/components/ui/switch";
import { updateTable } from "@/lib/design";
import { subjectTypeError } from "@/lib/design-subject";
import {
  EVENTS_BLOCK,
  featureBlocker,
  newSubject,
  RECORD_FEATURES,
  type RecordFeatureInfo,
  setEvents,
  setFeature,
  tableFeatures,
} from "@/lib/record-features";

import { CommitInput } from "./commit-input";
import { useDesign } from "./design-provider";

/**
 * Why `info`'s switch is off limits: a column in the way, a block the
 * preset can't take, or (to turn it off) a block another block requires.
 */
function switchBlocker(
  info: RecordFeatureInfo,
  on: boolean,
  blocker: string | undefined,
  conflict: string | undefined,
  requiredBy: readonly string[] | undefined,
): string | undefined {
  if (on) {
    return info.key === undefined && requiredBy !== undefined
      ? `Required by ${requiredBy.join(" and ")}, so it stays on.`
      : undefined;
  }

  return blocker ?? conflict;
}

/** The record features of an app table: it becomes a subject, and blocks reach its rows. */
export function FeaturesTab({ table }: { table: SchemaTable }): ReactElement {
  const { state, actions } = useDesign();
  const id = useId();
  const config = state.design.appTables?.[table.name];
  const resolved = useMemo(() => resolvePreset(state.preset), [state.preset]);

  const installed = useMemo(
    () => new Set(resolved.blocks.map((block) => block.name)),
    [resolved],
  );

  if (config === undefined) {
    return (
      <Empty className="border border-dashed p-6">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <LayersIcon aria-hidden="true" />
          </EmptyMedia>
          <EmptyTitle>Record features are for app tables</EmptyTitle>
          <EmptyDescription>
            The {table.module} block decides what its rows get. Add an app table
            to give its rows comments, files, tags, versions or search.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const active = new Set(
    tableFeatures(config, installed).map((info) => info.feature),
  );

  const { subject } = config;

  return (
    <div className="flex flex-col gap-6">
      <Field orientation="horizontal">
        <Switch
          id={`${id}-subject`}
          checked={subject !== undefined}
          onCheckedChange={(checked) => {
            actions.apply(
              updateTable(state.design, table.name, {
                subject: checked ? newSubject(table.name, config) : undefined,
              }),
            );
          }}
        />
        <FieldLabel htmlFor={`${id}-subject`}>
          Rows are records other blocks can reach
        </FieldLabel>
      </Field>
      {subject === undefined ? null : (
        <Field>
          <FieldLabel htmlFor={`${id}-type`}>Subject type</FieldLabel>
          <CommitInput
            id={`${id}-type`}
            label="Subject type"
            value={subject.type}
            placeholder={newSubject(table.name, config).type}
            validate={(next) =>
              subjectTypeError(state.design, table.name, next)
            }
            onCommit={(next) => {
              actions.apply(
                updateTable(state.design, table.name, {
                  subject: { ...subject, type: next },
                }),
              );
            }}
          />
          <FieldDescription>
            {subject.title === undefined
              ? "Comments and search name a row by its id. Add a text column to give it a title."
              : `Comments, notifications and search name a row by its ${subject.title} column.`}
          </FieldDescription>
        </Field>
      )}
      <section className="flex flex-col gap-2">
        <h3 className="text-sm font-medium">Features</h3>
        <p className="text-xs text-muted-foreground">
          Comments, attachments, tags and versions reach every record table once
          their block is on. Search, manual order and trash are set per table.
        </p>
        <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
          {RECORD_FEATURES.map((info) => {
            const on = active.has(info.feature);

            const block = resolved.blocks.find(
              (each) => each.name === info.block,
            );

            const blocked = switchBlocker(
              info,
              on,
              featureBlocker(config, info),
              installed.has(info.block)
                ? undefined
                : presetBlockConflict(state.preset, info.block),
              block !== undefined && !block.selected
                ? block.requiredBy
                : undefined,
            );

            return (
              <li key={info.feature} className="flex flex-col gap-1 px-3 py-2">
                <Field orientation="horizontal">
                  <Switch
                    id={`${id}-${info.feature}`}
                    checked={on}
                    disabled={blocked !== undefined}
                    onCheckedChange={(checked) => {
                      const next = setFeature(
                        state.design,
                        state.preset.blocks,
                        table.name,
                        info.feature,
                        checked,
                      );

                      actions.step(next.design, next.blocks);
                    }}
                  />
                  <FieldLabel htmlFor={`${id}-${info.feature}`}>
                    {info.label}
                  </FieldLabel>
                  {installed.has(info.block) ? null : (
                    <Badge variant="info-light" className="ml-auto">
                      Adds {info.block}
                    </Badge>
                  )}
                </Field>
                <p className="text-xs text-muted-foreground">
                  {blocked ?? info.description}
                </p>
              </li>
            );
          })}
        </ul>
      </section>
      <EventsSection
        table={table.name}
        on={config.events !== undefined}
        eventType={subject?.type ?? table.name}
        installed={installed.has(EVENTS_BLOCK)}
      />
    </div>
  );
}

/** The outbox events switch: inserts, updates and deletes emit events that rules and workflows react to. */
function EventsSection({
  table,
  on,
  eventType,
  installed,
}: {
  readonly table: string;
  readonly on: boolean;
  readonly eventType: string;
  readonly installed: boolean;
}): ReactElement {
  const { state, actions } = useDesign();
  const id = useId();

  const conflict =
    on || installed
      ? undefined
      : presetBlockConflict(state.preset, EVENTS_BLOCK);

  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-sm font-medium">Automations</h3>
      <p className="text-xs text-muted-foreground">
        Rules and workflows start from these events through outbox consumers.
      </p>
      <div className="flex flex-col gap-1 rounded-lg border border-border px-3 py-2">
        <Field orientation="horizontal">
          <Switch
            id={`${id}-events`}
            checked={on}
            disabled={conflict !== undefined}
            onCheckedChange={(checked) => {
              const next = setEvents(
                state.design,
                state.preset.blocks,
                table,
                checked,
              );

              actions.step(next.design, next.blocks);
            }}
          />
          <FieldLabel htmlFor={`${id}-events`}>Emit events</FieldLabel>
          {installed ? null : (
            <Badge variant="info-light" className="ml-auto">
              Adds {EVENTS_BLOCK}
            </Badge>
          )}
        </Field>
        <p className="text-xs text-muted-foreground">
          {conflict ??
            `Writes ${eventType}.created, ${eventType}.updated and ${eventType}.deleted to the outbox.`}
        </p>
      </div>
    </section>
  );
}
