"use client";

import type { ReactElement } from "react";

import {
  type AppTable,
  columnError,
  editTable,
  singular,
  type AppLookup,
  type AppRollup,
  filterColumns,
  fittedRollup,
  isRollupAggregate,
  lookupSources,
  readableColumns,
  ROLLUP_AGGREGATES,
  rollupColumns,
  rollupSources,
  tableWithComputed,
  tableWithoutComputed,
} from "better-supabase/create";
import { PlusIcon, Trash2Icon } from "lucide-react";
import { useId } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import type { InspectorPreset } from "./inspector-columns";

import { CommitInput } from "./commit-input";
import { useDesign } from "./design-provider";

type Tables = Readonly<Record<string, AppTable>>;

const NO_FILTER = "all";

/** A free column name for a new rollup or lookup: `base`, then `base_2` and so on. */
function freeName(
  config: AppTable,
  base: string,
  preset: InspectorPreset,
): string {
  let name = base;
  let index = 2;

  while (columnError(config, name, preset) !== undefined && index < 100) {
    name = `${base}_${String(index)}`;
    index += 1;
  }

  return name;
}

function SmallSelect({
  label,
  value,
  items,
  onChange,
}: {
  label: string;
  value: string;
  items: readonly { readonly value: string; readonly label: string }[];
  onChange: (next: string) => void;
}): ReactElement {
  return (
    <Select
      value={value}
      onValueChange={(next) => {
        const item = items.find((each) => each.value === next);

        if (item !== undefined) {
          onChange(item.value);
        }
      }}
    >
      <SelectTrigger size="sm" className="w-full" aria-label={label}>
        <SelectValue>
          {(current: string) => (
            <span className="truncate font-mono">
              {items.find((each) => each.value === current)?.label ?? current}
            </span>
          )}
        </SelectValue>
      </SelectTrigger>
      <SelectContent>
        {items.map((each) => (
          <SelectItem key={each.value} value={each.value} className="font-mono">
            {each.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function RollupFields({
  table,
  name,
  rollup,
  apply,
}: {
  table: string;
  name: string;
  rollup: AppRollup;
  apply: (next: AppRollup) => void;
}): ReactElement {
  const { state } = useDesign();
  const tables = state.design.appTables ?? {};
  const child = tables[rollup.table] ?? {};
  const sources = rollupSources(tables, table);

  const filters = filterColumns(child).flatMap(([column, options]) =>
    options.map((equals) => ({ column, equals })),
  );

  const filterIndex =
    rollup.where === undefined
      ? -1
      : filters.findIndex(
          (each) =>
            each.column === rollup.where?.column &&
            each.equals === rollup.where.equals,
        );

  return (
    <div className="grid grid-cols-2 gap-2">
      <SmallSelect
        label={`${name} source`}
        value={`${rollup.table}.${rollup.via}`}
        items={sources.map((each) => ({
          value: `${each.table}.${each.via}`,
          label: `${each.table} by ${each.via}`,
        }))}
        onChange={(next) => {
          const source = sources.find(
            (each) => `${each.table}.${each.via}` === next,
          );

          if (source !== undefined) {
            apply(
              fittedRollup(tables, {
                ...rollup,
                table: source.table,
                via: source.via,
              }),
            );
          }
        }}
      />
      <SmallSelect
        label={`${name} aggregate`}
        value={rollup.aggregate}
        items={ROLLUP_AGGREGATES.filter(
          (each) => each === "count" || rollupColumns(child, each).length > 0,
        ).map((each) => ({ value: each, label: each }))}
        onChange={(next) => {
          if (isRollupAggregate(next)) {
            apply(fittedRollup(tables, { ...rollup, aggregate: next }));
          }
        }}
      />
      {rollup.aggregate === "count" || rollup.column === undefined ? null : (
        <SmallSelect
          label={`${name} column`}
          value={rollup.column}
          items={rollupColumns(child, rollup.aggregate).map((each) => ({
            value: each,
            label: each,
          }))}
          onChange={(next) => {
            apply({ ...rollup, column: next });
          }}
        />
      )}
      {filters.length === 0 ? null : (
        <SmallSelect
          label={`${name} filter`}
          value={filterIndex === -1 ? NO_FILTER : String(filterIndex)}
          items={[
            { value: NO_FILTER, label: "every row" },
            ...filters.map((each, index) => ({
              value: String(index),
              label: `${each.column} = ${each.equals}`,
            })),
          ]}
          onChange={(next) => {
            const { where: _drop, ...rest } = rollup;
            const picked = filters[Number(next)];

            apply(
              next === NO_FILTER || picked === undefined
                ? rest
                : { ...rest, where: picked },
            );
          }}
        />
      )}
    </div>
  );
}

function LookupFields({
  table,
  name,
  lookup,
  apply,
}: {
  table: string;
  name: string;
  lookup: AppLookup;
  apply: (next: AppLookup) => void;
}): ReactElement {
  const { state } = useDesign();
  const tables = state.design.appTables ?? {};
  const sources = lookupSources(tables, table);
  const target = sources.find((each) => each.via === lookup.via)?.target;

  const columns =
    target === undefined
      ? []
      : readableColumns(tables[target] ?? {}).map(([column]) => column);

  return (
    <div className="grid grid-cols-2 gap-2">
      <SmallSelect
        label={`${name} link`}
        value={lookup.via}
        items={sources.map((each) => ({
          value: each.via,
          label: `${each.via} to ${each.target}`,
        }))}
        onChange={(next) => {
          const source = sources.find((each) => each.via === next);

          const first =
            source === undefined
              ? undefined
              : readableColumns(tables[source.target] ?? {})[0]?.[0];

          if (first !== undefined) {
            apply({ via: next, column: first });
          }
        }}
      />
      <SmallSelect
        label={`${name} column`}
        value={lookup.column}
        items={columns.map((each) => ({ value: each, label: each }))}
        onChange={(next) => {
          apply({ ...lookup, column: next });
        }}
      />
    </div>
  );
}

function newRollup(
  tables: Tables,
  table: string,
): { readonly name: string; readonly rollup: AppRollup } | undefined {
  const source = rollupSources(tables, table)[0];

  return source === undefined
    ? undefined
    : {
        name: `${source.table}_count`,
        rollup: { table: source.table, via: source.via, aggregate: "count" },
      };
}

function newLookup(
  tables: Tables,
  table: string,
): { readonly name: string; readonly lookup: AppLookup } | undefined {
  const source = lookupSources(tables, table)[0];

  const column =
    source === undefined
      ? undefined
      : readableColumns(tables[source.target] ?? {})[0]?.[0];

  return source === undefined || column === undefined
    ? undefined
    : {
        name: `${singular(source.target)}_${column}`,
        lookup: { via: source.via, column },
      };
}

/**
 * The rollups and lookups of an app table: read-only columns of its
 * `<table>_view`, picked from the links the design already has.
 */
export function ComputedSection({
  table,
  preset,
}: {
  table: string;
  preset: InspectorPreset;
}): ReactElement | null {
  const { state, actions } = useDesign();
  const id = useId();
  const tables = state.design.appTables ?? {};
  const config = tables[table];

  if (config === undefined) {
    return null;
  }

  const rollup = newRollup(tables, table);
  const lookup = newLookup(tables, table);

  const put = (
    name: string,
    computed: { readonly rollup: AppRollup } | { readonly lookup: AppLookup },
    previous: string = name,
  ): void => {
    actions.apply(
      editTable(state.design, table, (current) =>
        tableWithComputed(current, name, computed, previous),
      ),
    );
  };

  const addRollup = (): void => {
    if (rollup !== undefined) {
      put(freeName(config, rollup.name, preset), { rollup: rollup.rollup });
    }
  };

  const addLookup = (): void => {
    if (lookup !== undefined) {
      put(freeName(config, lookup.name, preset), { lookup: lookup.lookup });
    }
  };

  const entries = [
    ...Object.entries(config.rollups ?? {}).map(
      ([name, each]) => ({ name, rollup: each }) as const,
    ),
    ...Object.entries(config.lookups ?? {}).map(
      ([name, each]) => ({ name, lookup: each }) as const,
    ),
  ];

  const buttons = (
    <div className="flex flex-wrap gap-2">
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={rollup === undefined}
        onClick={addRollup}
      >
        <PlusIcon aria-hidden="true" />
        Add rollup
      </Button>
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={lookup === undefined}
        onClick={addLookup}
      >
        <PlusIcon aria-hidden="true" />
        Add lookup
      </Button>
    </div>
  );

  return (
    <section className="flex flex-col gap-3" aria-labelledby={`${id}-title`}>
      <div className="flex flex-col gap-1">
        <h3 id={`${id}-title`} className="text-sm font-medium">
          Computed
        </h3>
        <p className="text-xs text-muted-foreground">
          Read-only columns of <span className="font-mono">{table}_view</span>,
          worked out on every read with the reader&apos;s access.
        </p>
      </div>
      {entries.length === 0 ? (
        <Empty className="border border-dashed p-6">
          <EmptyHeader>
            <EmptyTitle>No computed columns yet</EmptyTitle>
            <EmptyDescription>
              {rollup === undefined && lookup === undefined
                ? `Link another app table to ${table}, or ${table} to one, to count, sum or show its values here.`
                : "A rollup counts or sums the rows that link here. A lookup shows a column of the row this one links to."}
            </EmptyDescription>
          </EmptyHeader>
          <EmptyContent>{buttons}</EmptyContent>
        </Empty>
      ) : (
        <>
          <ul
            className="flex flex-col divide-y"
            aria-label={`${table} computed columns`}
          >
            {entries.map((entry) => (
              <li key={entry.name} className="flex flex-col gap-2 py-3">
                <div className="flex items-center gap-2">
                  <div className="min-w-0 flex-1">
                    <CommitInput
                      id={`${id}-${entry.name}`}
                      value={entry.name}
                      label={`${entry.name} name`}
                      validate={(next) => columnError(config, next, preset)}
                      onCommit={(next) => {
                        put(
                          next,
                          "rollup" in entry
                            ? { rollup: entry.rollup }
                            : { lookup: entry.lookup },
                          entry.name,
                        );
                      }}
                    />
                  </div>
                  <Badge variant="outline">
                    {"rollup" in entry ? "rollup" : "lookup"}
                  </Badge>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Delete ${entry.name}`}
                    onClick={() => {
                      actions.apply(
                        editTable(state.design, table, (current) =>
                          tableWithoutComputed(current, entry.name),
                        ),
                      );
                    }}
                  >
                    <Trash2Icon aria-hidden="true" />
                  </Button>
                </div>
                {"rollup" in entry ? (
                  <RollupFields
                    table={table}
                    name={entry.name}
                    rollup={entry.rollup}
                    apply={(next) => {
                      put(entry.name, { rollup: next });
                    }}
                  />
                ) : (
                  <LookupFields
                    table={table}
                    name={entry.name}
                    lookup={entry.lookup}
                    apply={(next) => {
                      put(entry.name, { lookup: next });
                    }}
                  />
                )}
              </li>
            ))}
          </ul>
          {buttons}
        </>
      )}
    </section>
  );
}
