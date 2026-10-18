import type { ReactElement } from "react";

import { PRESET_NAMES, type PresetName, PRESETS } from "better-supabase/preset";

import { Badge } from "@/components/reui/badge";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { cn } from "@/lib/utils";

import { PRESET_CATEGORY } from "../preset-categories";

/**
 * The named presets as compact radio cards. `selected` is undefined once the
 * blocks no longer match any preset, so no card is checked.
 */
export function PresetPicker({
  selected,
  onSelect,
}: {
  selected: PresetName | undefined;
  onSelect: (name: PresetName) => void;
}): ReactElement {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="flex w-full items-center justify-between gap-2 pb-2">
        <span className="text-sm font-medium">Preset</span>
        {selected === undefined ? (
          <Badge variant="warning-light">Custom</Badge>
        ) : null}
      </legend>
      <div className="grid grid-cols-2 gap-2">
        {PRESET_NAMES.map((name) => {
          const preset = PRESETS[name];
          const checked = selected === name;

          return (
            <label
              key={name}
              title={preset.description}
              className={cn(
                "flex cursor-pointer items-center gap-2 rounded-lg border border-border bg-card px-2.5 py-2 transition-colors hover:bg-muted/50 has-focus-visible:ring-3 has-focus-visible:ring-ring/50",
                checked && "border-primary ring-1 ring-primary hover:bg-card",
              )}
            >
              <input
                type="radio"
                name="preset"
                value={name}
                checked={checked}
                onChange={() => {
                  onSelect(name);
                }}
                className="sr-only"
              />
              <CategoryIcon category={PRESET_CATEGORY[name]} size="sm" />
              <span className="flex min-w-0 flex-col">
                <span className="truncate text-sm leading-5 font-medium">
                  {preset.title}
                </span>
                <span className="text-xs leading-4 text-muted-foreground tabular-nums">
                  {preset.blocks.length}{" "}
                  {preset.blocks.length === 1 ? "block" : "blocks"}
                </span>
              </span>
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}
