import type { ReactElement } from "react";

import { ChevronDownIcon, ChevronUpIcon } from "lucide-react";
import { useId } from "react";

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { categoryStyle } from "@/features/blocks/categories";
import { BlockGlyph } from "@/features/blocks/components/block-icon";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { type BlockGroup, rowNote } from "@/lib/create";
import { cn } from "@/lib/utils";

function CategorySection({
  group,
  onToggle,
}: {
  group: BlockGroup;
  onToggle: (name: string) => void;
}): ReactElement {
  const ids = useId();

  const on = group.rows.filter(
    (row) => row.state.kind === "selected" || row.state.kind === "required",
  ).length;

  return (
    <Collapsible defaultOpen={on > 0} className="flex flex-col gap-1">
      <div className={cn("rounded-md", categoryStyle(group.category).tint)}>
        <CollapsibleTrigger className="group/category flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs font-medium text-foreground outline-none focus-visible:ring-3 focus-visible:ring-ring/50">
          <CategoryIcon category={group.category} size="sm" />
          {group.category}
          <span
            className={cn(
              "ml-auto font-normal tabular-nums",
              categoryStyle(group.category).text,
            )}
          >
            {on} of {group.rows.length}
          </span>
          <ChevronDownIcon
            aria-hidden="true"
            className="size-4 shrink-0 text-muted-foreground group-data-panel-open/category:hidden"
          />
          <ChevronUpIcon
            aria-hidden="true"
            className="hidden size-4 shrink-0 text-muted-foreground group-data-panel-open/category:inline"
          />
        </CollapsibleTrigger>
      </div>
      <CollapsibleContent keepMounted>
        <fieldset className="ml-4.5 flex flex-col gap-0.5 border-l border-border pl-2">
          <legend className="sr-only">{group.category}</legend>
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
                <BlockGlyph
                  name={row.name}
                  category={group.category}
                  className="mt-0.5 text-muted-foreground"
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
      </CollapsibleContent>
    </Collapsible>
  );
}

/**
 * Every block by category, each category its own collapsible. A block
 * another one needs is checked and locked with the reason; the checkboxes
 * stay native and mounted while closed, so the form is plain HTML.
 */
export function BlockPicker({
  groups,
  onToggle,
}: {
  groups: readonly BlockGroup[];
  onToggle: (name: string) => void;
}): ReactElement {
  return (
    <div className="flex flex-col gap-2">
      {groups.map((group) => (
        <CategorySection
          key={group.category}
          group={group}
          onToggle={onToggle}
        />
      ))}
    </div>
  );
}
