import { useId } from "react";

import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { type BlockGroup, rowNote } from "@/lib/create";
import { cn } from "@/lib/utils";

/**
 * Every block by category. A block another one needs is checked and locked
 * with the reason; the checkboxes stay native so the form is plain HTML.
 */
export function BlockPicker({
  groups,
  installed,
  onToggle,
}: {
  groups: readonly BlockGroup[];
  installed: number;
  onToggle: (name: string) => void;
}) {
  const ids = useId();

  return (
    <div className="flex flex-col gap-6">
      <p className="flex items-baseline justify-between gap-2">
        <span className="text-base font-semibold tracking-tight">Blocks</span>
        <span className="text-xs text-muted-foreground tabular-nums">
          {installed} installed
        </span>
      </p>
      {groups.map((group) => {
        const on = group.rows.filter(
          (row) =>
            row.state.kind === "selected" || row.state.kind === "required",
        ).length;

        return (
          <fieldset key={group.category} className="flex flex-col gap-2">
            <legend className="flex w-full items-center gap-2 pb-2">
              <CategoryIcon category={group.category} size="sm" />
              <span className="text-sm font-medium">{group.category}</span>
              <span className="ml-auto text-xs text-muted-foreground tabular-nums">
                {on} of {group.rows.length}
              </span>
            </legend>
            <div className="grid grid-cols-1 gap-1 sm:grid-cols-2">
              {group.rows.map((row) => {
                const note = rowNote(row.state);
                const noteId = `${ids}-${row.name}-note`;

                const locked =
                  row.state.kind === "required" ||
                  row.state.kind === "conflict";

                const checked =
                  row.state.kind === "selected" ||
                  row.state.kind === "required";

                return (
                  <label
                    key={row.name}
                    title={row.description}
                    className={cn(
                      "flex items-start gap-2.5 rounded-lg border border-transparent px-2.5 py-2 text-sm transition-colors",
                      locked
                        ? "cursor-not-allowed"
                        : "cursor-pointer hover:bg-muted/60",
                      checked && "border-border bg-muted/40",
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
            </div>
          </fieldset>
        );
      })}
    </div>
  );
}
