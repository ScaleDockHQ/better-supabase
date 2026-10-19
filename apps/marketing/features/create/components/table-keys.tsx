"use client";

import type { ReactElement } from "react";

import {
  type SchemaTable,
  type AppTableId,
  setTableId,
  updateTable,
} from "better-supabase/create";
import { PlusIcon, Trash2Icon } from "lucide-react";
import { useId } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import { CommitInput } from "./commit-input";
import { useDesign } from "./design-provider";

type KeySets = readonly (readonly string[])[];

const ID_TYPES: readonly {
  readonly value: AppTableId;
  readonly label: string;
}[] = [
  { value: "uuid", label: "UUID, random" },
  { value: "bigint", label: "Number, counting up" },
];

function isTableId(value: unknown): value is AppTableId {
  return ID_TYPES.some((each) => each.value === value);
}

/** Sets of columns that are unique together, or indexed together. */
function KeySetsEditor({
  label,
  description,
  sets,
  columns,
  onChange,
}: {
  label: string;
  description: string;
  sets: KeySets;
  columns: readonly string[];
  onChange: (sets: KeySets | undefined) => void;
}): ReactElement {
  const id = useId();

  const replace = (index: number, next: readonly string[]): void => {
    const edited = sets
      .map((set, each) => (each === index ? next : set))
      .filter((set) => set.length > 0);

    onChange(edited.length === 0 ? undefined : edited);
  };

  return (
    <Field>
      <FieldLabel id={`${id}-label`}>{label}</FieldLabel>
      <FieldDescription>{description}</FieldDescription>
      {sets.length === 0 ? null : (
        <ul className="flex flex-col gap-2" aria-labelledby={`${id}-label`}>
          {sets.map((set, index) => (
            <li
              key={`${String(index)}:${set.join(",")}`}
              className="flex items-center gap-2"
            >
              <Select
                multiple
                value={[...set]}
                onValueChange={(next) => {
                  // Keeps the table's column order, which is the key's order.
                  const picked = new Set<unknown>(next);
                  replace(
                    index,
                    columns.filter((column) => picked.has(column)),
                  );
                }}
              >
                <SelectTrigger
                  size="sm"
                  className="w-full"
                  aria-label={`${label} ${String(index + 1)}`}
                >
                  <SelectValue>
                    {(value: string[]) => (
                      <span className="truncate font-mono">
                        {value.join(", ")}
                      </span>
                    )}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent>
                  {columns.map((column) => (
                    <SelectItem
                      key={column}
                      value={column}
                      className="font-mono"
                    >
                      {column}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                aria-label={`Delete ${label.toLowerCase()} on ${set.join(", ")}`}
                onClick={() => {
                  replace(index, []);
                }}
              >
                <Trash2Icon aria-hidden="true" />
              </Button>
            </li>
          ))}
        </ul>
      )}
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="self-start"
        disabled={columns.length < 2}
        onClick={() => {
          onChange([...sets, columns.slice(0, 2)]);
        }}
      >
        <PlusIcon aria-hidden="true" />
        Add {label.toLowerCase()}
      </Button>
    </Field>
  );
}

/** An app table's id type, description, composite unique keys and indexes. */
export function TableKeyFields({
  table,
}: {
  table: SchemaTable;
}): ReactElement | null {
  const { state, actions } = useDesign();
  const id = useId();
  const config = state.design.appTables?.[table.name];

  if (config === undefined) {
    return null;
  }

  const columns = table.columns
    .map((column) => column.name)
    .filter((name) => name !== "id");

  return (
    <>
      <Field>
        <FieldLabel htmlFor={`${id}-id`}>Row id</FieldLabel>
        <Select
          value={config.id ?? "uuid"}
          onValueChange={(next) => {
            if (isTableId(next)) {
              actions.apply(setTableId(state.design, table.name, next));
            }
          }}
        >
          <SelectTrigger id={`${id}-id`} size="sm" className="w-full">
            <SelectValue>
              {(value: string) =>
                ID_TYPES.find((each) => each.value === value)?.label ?? value
              }
            </SelectValue>
          </SelectTrigger>
          <SelectContent>
            {ID_TYPES.map((each) => (
              <SelectItem key={each.value} value={each.value}>
                {each.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <FieldDescription>
          Links from other app tables change type with it.
        </FieldDescription>
      </Field>
      <Field>
        <FieldLabel htmlFor={`${id}-comment`}>Description</FieldLabel>
        <CommitInput
          id={`${id}-comment`}
          label="Description"
          mono={false}
          value={config.comment ?? ""}
          placeholder="What a row is, for the database comment"
          validate={(next) =>
            next.length > 1000 ? "Use at most 1000 characters." : undefined
          }
          onCommit={(next) => {
            actions.apply(
              updateTable(state.design, table.name, {
                comment: next.trim() === "" ? undefined : next.trim(),
              }),
            );
          }}
        />
      </Field>
      <KeySetsEditor
        label="Unique key"
        description="No two rows share the same values in all of these columns."
        sets={config.unique ?? []}
        columns={columns}
        onChange={(unique) => {
          actions.apply(updateTable(state.design, table.name, { unique }));
        }}
      />
      <KeySetsEditor
        label="Index"
        description="Speeds up filters and sorts on these columns, in the order the table lists them."
        sets={config.indexes ?? []}
        columns={columns}
        onChange={(indexes) => {
          actions.apply(updateTable(state.design, table.name, { indexes }));
        }}
      />
    </>
  );
}
