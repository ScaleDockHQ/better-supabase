import type { ReactElement } from "react";

import { useId } from "react";

import { BlockIcon } from "@/features/blocks/components/block-icon";
import { type BlockGroup, rowNote } from "@/lib/create";
import { cn } from "@/lib/utils";

/**
 * Every block by category. A block another one needs is checked and locked
 * with the reason; the checkboxes stay native so the form is plain HTML.
 */
export function BlockPicker({
  groups,
  onToggle,
}: {
  groups: readonly BlockGroup[];
  onToggle: (name: string) => void;
}): ReactElement {
  const ids = useId();

  return (
    <div className="flex flex-col gap-4">
      {groups.map((group) => {
        const on = group.rows.filter(
          (row) =>
            row.state.kind === "selected" || row.state.kind === "required",
        ).length;

        return (
          <fieldset key={group.category} className="flex flex-col gap-1">
            <legend className="flex w-full items-center gap-2 pb-1">
              <span className="text-xs font-medium text-muted-foreground">
                {group.category}
              </span>
              <span className="ml-auto text-xs text-muted-foreground tabular-nums">
                {on} of {group.rows.length}
              </span>
            </legend>
            {group.rows.map((row) => {
              const note = rowNote(row.state);
              const noteId = `${ids}-${row.name}-note`;

              const locked =
                row.state.kind === "required" || row.state.kind === "conflict";

              const checked =
                row.state.kind === "selected" || row.state.kind === "required";

              return (
                <label
                  key={row.name}
                  title={row.description}
                  className={cn(
                    "flex items-start gap-2 rounded-md px-2 py-1.5 text-sm transition-colors",
                    locked
                      ? "cursor-not-allowed"
                      : "cursor-pointer hover:bg-muted/60",
                    checked && "bg-muted/40",
                  )}
                >
                  <input
                    type="checkbox"
                    name="block"
                    value={row.name}
                    checked={checked}
                    disabled={locked}
                    aria-describedby={note === undefined ? undefined : noteId}
                    onChange={() => {
                      onToggle(row.name);
                    }}
                    className="mt-0.5 size-4 shrink-0 accent-primary"
                  />
                  <BlockIcon
                    name={row.name}
                    category={group.category}
                    size="xs"
                  />
                  <span className="flex min-w-0 flex-col">
                    <span className="leading-5">{row.title}</span>
                    {note === undefined ? null : (
                      <span
                        id={noteId}
                        className={cn(
                          "text-xs leading-5",
                          row.state.kind === "conflict"
                            ? "text-destructive"
                            : "text-muted-foreground",
                        )}
                      >
                        {note}
                      </span>
                    )}
                  </span>
                </label>
              );
            })}
          </fieldset>
        );
      })}
    </div>
  );
}
