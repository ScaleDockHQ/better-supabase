"use client";

import type { Preset } from "better-supabase/preset";
import type { ReactElement } from "react";

import {
  type SchemaData,
  type SchemaTable,
  COLUMN_KINDS,
  type ColumnKind,
  kindById,
  kindOf,
  setColumnKind,
  type AppColumn,
  appTableId,
  columnError,
  defaultError,
  deleteColumn,
  deleteExtraColumn,
  identifierError,
  isAppTable,
  renameColumn,
  renameTable,
  setColumn,
  setExtraColumn,
  takesBounds,
} from "better-supabase/create";
import { PlusIcon, Trash2Icon } from "lucide-react";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";

import type { InspectorTab } from "./schema-nodes";

import { BoundsFields, KindSelect, OptionsEditor } from "./column-fields";
import { CommitInput } from "./commit-input";
import { useDesign } from "./design-provider";
import { ComputedSection } from "./inspector-computed";

/** The kinds a block table's extra column can take: plain Postgres types. */
const PLAIN_KINDS = COLUMN_KINDS.filter(
  (kind) => Object.keys(kind.column).length === 1,
);

/** The preset fields the inspector reads. */
export type InspectorPreset = Pick<Preset, "scope" | "tenantName" | "idType">;

export function OverviewTab({
  table,
  data,
  preset,
  onOpen,
  onDelete,
}: {
  table: SchemaTable;
  data: SchemaData;
  preset: InspectorPreset;
  onOpen: (id: string, tab?: InspectorTab) => void;
  onDelete: (id: string) => void;
}): ReactElement {
  const { state, actions } = useDesign();
  const id = useId();
  const app = isAppTable(table);
  const taken = new Set(data.tables.map((each) => each.name));

  const scope =
    table.tenantColumn === null
      ? table.columns.some((column) => column.name === "user_id")
        ? "Per user"
        : "Shared"
      : `By ${preset.tenantName} (${table.tenantColumn})`;

  return (
    <div className="flex flex-col gap-6">
      {app ? (
        <Field>
          <FieldLabel htmlFor={`${id}-name`}>Table name</FieldLabel>
          <CommitInput
            id={`${id}-name`}
            label="Table name"
            value={table.name}
            validate={(next) =>
              identifierError(next) ??
              (taken.has(next)
                ? `The schema already has a ${next} table.`
                : undefined)
            }
            onCommit={(next) => {
              actions.apply(renameTable(state.design, table.name, next));
              onOpen(appTableId(next), "overview");
            }}
          />
          <FieldDescription>
            The table goes in the <code className="font-mono">public</code>{" "}
            schema.
          </FieldDescription>
        </Field>
      ) : null}
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
        <dt className="text-muted-foreground">Table</dt>
        <dd className="font-mono">{table.id}</dd>
        <dt className="text-muted-foreground">From</dt>
        <dd>{app ? "Your app" : `The ${table.module} block`}</dd>
        <dt className="text-muted-foreground">Columns</dt>
        <dd className="tabular-nums">{table.columns.length}</dd>
        <dt className="text-muted-foreground">Primary key</dt>
        <dd className="font-mono">{table.primaryKey.join(", ") || "None"}</dd>
        <dt className="text-muted-foreground">Rows</dt>
        <dd>{scope}</dd>
      </dl>
      {app ? (
        <Button
          type="button"
          variant="destructive"
          size="sm"
          className="self-start"
          onClick={() => {
            onDelete(table.id);
          }}
        >
          <Trash2Icon aria-hidden="true" />
          Delete table
        </Button>
      ) : null}
    </div>
  );
}

function AppColumnRow({
  table,
  name,
  column,
  preset,
}: {
  table: string;
  name: string;
  column: AppColumn;
  preset: InspectorPreset;
}): ReactElement {
  const { state, actions } = useDesign();
  const id = useId();
  const config = state.design.appTables?.[table] ?? {};

  const update = (patch: Partial<AppColumn>): void => {
    actions.apply(
      setColumn(state.design, table, name, { ...column, ...patch }),
    );
  };

  const replace = (next: AppColumn): void => {
    actions.apply(setColumn(state.design, table, name, next));
  };

  const kind = kindOf(column);

  return (
    <li className="flex flex-col gap-3 rounded-lg border border-border p-3">
      <div className="flex items-start gap-2">
        <div className="flex-1">
          <CommitInput
            id={`${id}-name`}
            label="Column name"
            value={name}
            validate={(next) => columnError(config, next, preset)}
            onCommit={(next) => {
              actions.apply(renameColumn(state.design, table, name, next));
            }}
          />
        </div>
        <div className="w-40">
          <KindSelect
            kinds={COLUMN_KINDS}
            value={kind.id}
            disabled={kind.drawn === true}
            onChange={(next) => {
              actions.apply(
                setColumnKind(state.design, table, name, next).design,
              );
            }}
          />
        </div>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          aria-label={`Delete ${name}`}
          onClick={() => {
            actions.apply(deleteColumn(state.design, table, name));
          }}
        >
          <Trash2Icon aria-hidden="true" />
        </Button>
      </div>
      {kind.drawn === true ? (
        <p className="text-xs text-muted-foreground">
          A link to {column.references?.table}. Delete it on the canvas to
          change its type.
        </p>
      ) : null}
      <div className="flex flex-wrap items-center gap-4">
        <Field orientation="horizontal" className="w-auto">
          <Switch
            id={`${id}-required`}
            disabled={column.identity === true}
            size="sm"
            checked={column.nullable === false}
            onCheckedChange={(checked) => {
              update({ nullable: !checked });
            }}
          />
          <FieldLabel htmlFor={`${id}-required`}>Required</FieldLabel>
        </Field>
        <Field orientation="horizontal" className="w-auto">
          <Switch
            id={`${id}-unique`}
            size="sm"
            checked={column.unique === true}
            onCheckedChange={(checked) => {
              update({ unique: checked });
            }}
          />
          <FieldLabel htmlFor={`${id}-unique`}>Unique</FieldLabel>
        </Field>
      </div>
      {column.options === undefined ? null : (
        <OptionsEditor
          options={column.options}
          onChange={(options) => {
            update({ options });
          }}
        />
      )}
      {column.identity === true ? null : (
        <Field>
          <FieldLabel htmlFor={`${id}-default`}>Default</FieldLabel>
          <CommitInput
            id={`${id}-default`}
            label="Default"
            value={column.default ?? ""}
            placeholder="now(), 0, 'draft'"
            validate={(next) => defaultError(column.type, next)}
            onCommit={(next) => {
              const { default: _drop, ...rest } = column;
              replace(
                next.trim() === "" ? rest : { ...rest, default: next.trim() },
              );
            }}
          />
        </Field>
      )}
      {takesBounds(column.type) &&
      column.options === undefined &&
      column.identity !== true ? (
        <BoundsFields column={column} onChange={replace} />
      ) : null}
      <Field>
        <FieldLabel htmlFor={`${id}-comment`}>Description</FieldLabel>
        <CommitInput
          id={`${id}-comment`}
          label="Description"
          mono={false}
          value={column.comment ?? ""}
          placeholder="What the column holds, for the database comment"
          validate={(next) =>
            next.length > 1000 ? "Use at most 1000 characters." : undefined
          }
          onCommit={(next) => {
            const { comment: _drop, ...rest } = column;
            replace(
              next.trim() === "" ? rest : { ...rest, comment: next.trim() },
            );
          }}
        />
      </Field>
    </li>
  );
}

function AddColumnForm({
  kinds,
  validate,
  onAdd,
}: {
  kinds: readonly ColumnKind[];
  validate: (name: string) => string | undefined;
  onAdd: (name: string, kind: ColumnKind) => void;
}): ReactElement {
  const id = useId();
  const [name, setName] = useState("");
  const [kind, setKind] = useState("text");
  const error = name === "" ? undefined : validate(name);

  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(event) => {
        event.preventDefault();

        const picked = kindById(kind);

        if (name !== "" && error === undefined && picked !== undefined) {
          onAdd(name, picked);
          setName("");
        }
      }}
    >
      <FieldLabel htmlFor={`${id}-name`}>Add a column</FieldLabel>
      <div className="flex items-start gap-2">
        <div className="flex flex-1 flex-col gap-1">
          <Input
            id={`${id}-name`}
            className="font-mono"
            placeholder="title"
            value={name}
            aria-invalid={error === undefined ? undefined : true}
            onChange={(event) => {
              setName(event.target.value);
            }}
          />
          {error === undefined ? null : <FieldError>{error}</FieldError>}
        </div>
        <div className="w-40">
          <KindSelect
            kinds={kinds}
            value={kind}
            onChange={(next) => {
              setKind(next.id);
            }}
          />
        </div>
        <Button
          type="submit"
          size="sm"
          disabled={name === "" || error !== undefined}
        >
          <PlusIcon aria-hidden="true" />
          Add
        </Button>
      </div>
    </form>
  );
}

function ReadOnlyColumns({ table }: { table: SchemaTable }): ReactElement {
  return (
    <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
      {table.columns.map((column) => (
        <li
          key={column.name}
          className="flex items-center gap-2 px-3 py-2 text-sm"
        >
          <span className="min-w-0 flex-1 truncate font-mono">
            {column.name}
          </span>
          {table.primaryKey.includes(column.name) ? (
            <Badge variant="outline">key</Badge>
          ) : null}
          {column.unique ? <Badge variant="outline">unique</Badge> : null}
          <span className="truncate font-mono text-xs text-muted-foreground">
            {column.type}
            {column.nullable ? "" : " not null"}
            {column.default === null ? "" : ` default ${column.default}`}
          </span>
        </li>
      ))}
    </ul>
  );
}

export function ColumnsTab({
  table,
  data,
  preset,
}: {
  table: SchemaTable;
  data: SchemaData;
  preset: InspectorPreset;
}): ReactElement {
  const { state, actions } = useDesign();
  const config = state.design.appTables?.[table.name];

  if (isAppTable(table) && config !== undefined) {
    const own = Object.entries(config.columns ?? {});

    const implicit = table.columns.filter(
      (column) => config.columns?.[column.name] === undefined,
    );

    return (
      <div className="flex flex-col gap-6">
        <AddColumnForm
          kinds={COLUMN_KINDS}
          validate={(name) => columnError(config, name, preset)}
          onAdd={(name, kind) => {
            actions.apply(
              setColumnKind(
                setColumn(state.design, table.name, name, {
                  type: kind.column.type,
                }),
                table.name,
                name,
                kind,
              ).design,
            );
          }}
        />
        {own.length === 0 ? (
          <Empty className="border border-dashed p-6">
            <EmptyHeader>
              <EmptyTitle>No columns of your own yet</EmptyTitle>
              <EmptyDescription>
                Add one above, or drag the handle on the table onto another
                table to add a foreign key.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <ul className="flex flex-col gap-2">
            {own.map(([name, column]) => (
              <AppColumnRow
                key={name}
                table={table.name}
                name={name}
                column={column}
                preset={preset}
              />
            ))}
          </ul>
        )}
        <section className="flex flex-col gap-2">
          <h3 className="text-sm font-medium">Added for you</h3>
          <ReadOnlyColumns table={{ ...table, columns: implicit }} />
        </section>
        <ComputedSection table={table.name} preset={preset} />
      </div>
    );
  }

  const extra = data.extraColumns.includes(table.id)
    ? Object.entries(state.design.extraColumns?.[table.module] ?? {})
    : undefined;

  const names = new Set(table.columns.map((column) => column.name));

  return (
    <div className="flex flex-col gap-6">
      {extra === undefined ? null : (
        <section className="flex flex-col gap-3">
          <AddColumnForm
            kinds={PLAIN_KINDS}
            validate={(name) =>
              identifierError(name) ??
              (names.has(name)
                ? `The table already has a ${name} column.`
                : undefined)
            }
            onAdd={(name, kind) => {
              actions.apply(
                setExtraColumn(
                  state.design,
                  table.module,
                  name,
                  kind.column.type,
                ),
              );
            }}
          />
          <p className="text-xs text-muted-foreground">
            Extra columns go in{" "}
            <code className="font-mono">
              blocks.{table.module}.options.extraColumns
            </code>
            .
          </p>
          {extra.length === 0 ? null : (
            <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
              {extra.map(([name, type]) => (
                <li
                  key={name}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm"
                >
                  <span className="min-w-0 flex-1 truncate font-mono">
                    {name}
                  </span>
                  <span className="font-mono text-xs text-muted-foreground">
                    {type}
                  </span>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Delete ${name}`}
                    onClick={() => {
                      actions.apply(
                        deleteExtraColumn(state.design, table.module, name),
                      );
                    }}
                  >
                    <Trash2Icon aria-hidden="true" />
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
      <ReadOnlyColumns table={table} />
    </div>
  );
}
