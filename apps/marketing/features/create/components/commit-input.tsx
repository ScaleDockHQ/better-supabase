"use client";

import type { ReactElement } from "react";

import { useState } from "react";

import { FieldError } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

/** A text field that commits on blur and Enter, and shows why a value is refused. */
export function CommitInput({
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
