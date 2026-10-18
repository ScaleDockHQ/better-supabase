"use client";

import type { Preset } from "better-supabase/preset";
import type { ReactElement } from "react";

import { PlusIcon, Trash2Icon } from "lucide-react";
import { useId, useState } from "react";

import type { SchemaData, SchemaTable } from "@/lib/schema";

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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import {
  type AppColumn,
  type AppColumnType,
  APP_COLUMN_TYPES,
  appTableId,
  columnError,
  defaultError,
  deleteColumn,
  deleteExtraColumn,
  identifierError,
  isAppTable,
  renameColumn,
  renameTable,
  retyped,
  setColumn,
  setExtraColumn,
} from "@/lib/design";

import type { InspectorTab } from "./schema-nodes";

import { useDesign } from "./design-provider";

/** The preset fields the inspector reads. */
export type InspectorPreset = Pick<Preset, "scope" | "tenantName" | "idType">;

function isColumnType(value: unknown): value is AppColumnType {
  return APP_COLUMN_TYPES.some((type) => type === value);
}

function TypeSelect({
  id,
  value,
  onChange,
}: {
  id?: string;
  value: AppColumnType;
  onChange: (type: AppColumnType) => void;
}): ReactElement {
  return (
    <Select
      value={value}
      onValueChange={(next) => {
        if (isColumnType(next)) {
          onChange(next);
        }
      }}
    >
      <SelectTrigger
        id={id}
        size="sm"
        className="w-full"
        aria-label="Column type"
      >
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {APP_COLUMN_TYPES.map((type) => (
          <SelectItem key={type} value={type} className="font-mono">
            {type}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

/** A text field that commits on blur and Enter, and shows why a value is refused. */
function CommitInput({
  id,
  value,
  label,
  validate,
  onCommit,
  placeholder,
  mono = true,
}: {
  id: string;
  value: string;
  label: string;
  validate?: (next: string) => string | undefined;
  onCommit: (next: string) => void;
  placeholder?: string;
  mono?: boolean;
}): ReactElement {
  const [draft, setDraft] = useState(value);
  const [source, setSource] = useState(value);

  if (source !== value) {
    setSource(value);
    setDraft(value);
  }

  const error = draft === value ? undefined : validate?.(draft);

  const commit = (): void => {
    if (draft !== value && error === undefined) {
      onCommit(draft);
    }
  };

  return (
    <div className="flex flex-col gap-1">
      <Input
        id={id}
        aria-label={label}
        aria-invalid={error === undefined ? undefined : true}
        className={mono ? "font-mono" : ""}
        value={draft}
        placeholder={placeholder}
        onChange={(event) => {
          setDraft(event.target.value);
        }}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            commit();
          } else if (event.key === "Escape") {
            setDraft(value);
          }
        }}
      />
      {error === undefined ? null : <FieldError>{error}</FieldError>}
    </div>
  );
}

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
        : "Not scoped"
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
        <div className="w-32">
          <TypeSelect
            value={column.type}
            onChange={(type) => {
              actions.apply(
                setColumn(state.design, table, name, retyped(column, type)),
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
      <div className="flex flex-wrap items-center gap-4">
        <Field orientation="horizontal" className="w-auto">
          <Switch
            id={`${id}-required`}
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
            actions.apply(
              setColumn(
                state.design,
                table,
                name,
                next.trim() === "" ? rest : { ...rest, default: next.trim() },
              ),
            );
          }}
        />
      </Field>
    </li>
  );
}

function AddColumnForm({
  validate,
  onAdd,
}: {
  validate: (name: string) => string | undefined;
  onAdd: (name: string, type: AppColumnType) => void;
}): ReactElement {
  const id = useId();
  const [name, setName] = useState("");
  const [type, setType] = useState<AppColumnType>("text");
  const error = name === "" ? undefined : validate(name);

  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(event) => {
        event.preventDefault();

        if (name !== "" && error === undefined) {
          onAdd(name, type);
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
        <div className="w-32">
          <TypeSelect value={type} onChange={setType} />
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
          validate={(name) => columnError(config, name, preset)}
          onAdd={(name, type) => {
            actions.apply(setColumn(state.design, table.name, name, { type }));
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
            validate={(name) =>
              identifierError(name) ??
              (names.has(name)
                ? `The table already has a ${name} column.`
                : undefined)
            }
            onAdd={(name, type) => {
              actions.apply(
                setExtraColumn(state.design, table.module, name, type),
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
