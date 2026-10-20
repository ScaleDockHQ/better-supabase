"use client";

import type { ReactElement } from "react";

import {
  type AppColumn,
  type AppColumnAccess,
  COLUMN_KINDS,
  type ColumnKind,
  KIND_GROUPS,
  kindById,
  boundError,
  optionError,
  withBounds,
} from "better-supabase/create";
import { XIcon } from "lucide-react";
import { useId, useState } from "react";

import { Button } from "@/components/ui/button";
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
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import { CommitInput } from "./commit-input";

/** The column type picker, grouped as Text, Number, Date and time, Choice, Relation and Other. */
export function KindSelect({
  id,
  kinds,
  value,
  onChange,
  disabled,
}: {
  id?: string;
  kinds: readonly ColumnKind[];
  value: string;
  onChange: (kind: ColumnKind) => void;
  disabled?: boolean;
}): ReactElement {
  return (
    <Select
      value={value}
      disabled={disabled}
      onValueChange={(next) => {
        const kind = COLUMN_KINDS.find((each) => each.id === next);

        if (kind !== undefined && kind.drawn !== true) {
          onChange(kind);
        }
      }}
    >
      <SelectTrigger
        id={id}
        size="sm"
        className="w-full"
        aria-label="Column type"
      >
        <SelectValue>
          {(next: string) => kindById(next)?.label ?? next}
        </SelectValue>
      </SelectTrigger>
      <SelectContent>
        {KIND_GROUPS.map((group) => {
          const items = kinds.filter((kind) => kind.group === group);

          return items.length === 0 ? null : (
            <SelectGroup key={group}>
              <SelectLabel>{group}</SelectLabel>
              {items.map((kind) => (
                <SelectItem
                  key={kind.id}
                  value={kind.id}
                  disabled={kind.drawn === true}
                >
                  {kind.label}
                </SelectItem>
              ))}
            </SelectGroup>
          );
        })}
      </SelectContent>
    </Select>
  );
}

const ACCESS_CHOICES = [
  {
    value: "write",
    label: "Members read and write",
    description:
      "Signed-in members read and write it, within the row policies.",
  },
  {
    value: "read",
    label: "Members read only",
    description:
      "Signed-in members read it; only server code with the service role writes it.",
  },
  {
    value: "server",
    label: "Server only",
    description:
      "Signed-in members can't read or write it; only server code with the service role can.",
  },
] as const;

type AccessChoice = (typeof ACCESS_CHOICES)[number]["value"];

const choiceOf = (value: string) =>
  ACCESS_CHOICES.find((each) => each.value === value);

/** Who reads and writes a column, as column grants: everyone, read only, or server only. */
export function AccessSelect({
  value,
  onChange,
}: {
  value: AppColumnAccess | undefined;
  onChange: (access: AppColumnAccess | undefined) => void;
}): ReactElement {
  const id = useId();
  const current: AccessChoice = value ?? "write";

  return (
    <Field>
      <FieldLabel htmlFor={`${id}-access`}>Access</FieldLabel>
      <Select
        value={current}
        onValueChange={(next) => {
          const choice = next === null ? undefined : choiceOf(next);

          if (choice !== undefined) {
            onChange(choice.value === "write" ? undefined : choice.value);
          }
        }}
      >
        <SelectTrigger id={`${id}-access`} size="sm" className="w-full">
          <SelectValue>
            {(next: string) => choiceOf(next)?.label ?? next}
          </SelectValue>
        </SelectTrigger>
        <SelectContent>
          {ACCESS_CHOICES.map((each) => (
            <SelectItem key={each.value} value={each.value}>
              {each.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <FieldDescription>{choiceOf(current)?.description}</FieldDescription>
    </Field>
  );
}

/** The values of a single or multi-select: remove one with its button, add one with Enter. */
export function OptionsEditor({
  options,
  onChange,
}: {
  options: readonly string[];
  onChange: (options: readonly string[]) => void;
}): ReactElement {
  const id = useId();
  const [draft, setDraft] = useState("");
  const option = draft.trim();
  const error = option === "" ? undefined : optionError(options, option);

  return (
    <Field>
      <FieldLabel htmlFor={`${id}-option`}>Options</FieldLabel>
      <ul className="flex flex-wrap gap-1" aria-label="Options">
        {options.map((each) => (
          <li key={each}>
            <Button
              type="button"
              variant="outline"
              size="xs"
              aria-label={`Remove option ${each}`}
              disabled={options.length === 1}
              onClick={() => {
                onChange(options.filter((other) => other !== each));
              }}
            >
              {each}
              <XIcon aria-hidden="true" data-icon="inline-end" />
            </Button>
          </li>
        ))}
      </ul>
      <Input
        id={`${id}-option`}
        value={draft}
        placeholder="Add an option and press Enter"
        aria-invalid={error === undefined ? undefined : true}
        onChange={(event) => {
          setDraft(event.target.value);
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();

            if (option !== "" && error === undefined) {
              onChange([...options, option]);
              setDraft("");
            }
          }
        }}
      />
      {error === undefined ? null : <FieldError>{error}</FieldError>}
    </Field>
  );
}

/** The smallest and largest value, or the shortest and longest text. */
export function BoundsFields({
  column,
  onChange,
}: {
  column: AppColumn;
  onChange: (column: AppColumn) => void;
}): ReactElement {
  const id = useId();
  const text = column.type === "text";

  const commit = (side: "min" | "max", next: string): void => {
    const trimmed = next.trim();
    const value = trimmed === "" ? undefined : Number(trimmed);

    onChange(
      withBounds(
        column,
        side === "min"
          ? { min: value, max: column.max }
          : { min: column.min, max: value },
      ),
    );
  };

  return (
    <div className="grid grid-cols-2 gap-2">
      {(["min", "max"] as const).map((side) => {
        const label = text
          ? side === "min"
            ? "Shortest"
            : "Longest"
          : side === "min"
            ? "Smallest"
            : "Largest";

        return (
          <Field key={side}>
            <FieldLabel htmlFor={`${id}-${side}`}>{label}</FieldLabel>
            <CommitInput
              id={`${id}-${side}`}
              label={label}
              value={column[side] === undefined ? "" : String(column[side])}
              placeholder={text ? "characters" : "any"}
              validate={(next) => boundError(column, side, next)}
              onCommit={(next) => {
                commit(side, next);
              }}
            />
          </Field>
        );
      })}
    </div>
  );
}
