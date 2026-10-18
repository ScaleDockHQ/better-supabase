import { PRESET_NAMES, type PresetName, PRESETS } from "better-supabase/preset";

import { Badge } from "@/components/reui/badge";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { cn } from "@/lib/utils";

import { PRESET_CATEGORY } from "../preset-categories";

/**
 * The named presets as radio cards. `selected` is undefined once the blocks
 * no longer match any preset, so no card is checked.
 */
export function PresetPicker({
  selected,
  onSelect,
}: {
  selected: PresetName | undefined;
  onSelect: (name: PresetName) => void;
}) {
  return (
    <fieldset className="flex flex-col gap-3">
      <legend className="flex w-full items-center justify-between gap-2 pb-3">
        <span className="text-base font-semibold tracking-tight">
          Start from a preset
        </span>
        {selected === undefined ? (
          <Badge variant="warning-light">Custom selection</Badge>
        ) : null}
      </legend>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 2xl:grid-cols-4">
        {PRESET_NAMES.map((name) => {
          const preset = PRESETS[name];
          const checked = selected === name;

          return (
            <label
              key={name}
              className={cn(
                "flex cursor-pointer flex-col gap-3 rounded-xl border border-border bg-card p-4 transition-colors hover:bg-muted/50 has-focus-visible:ring-3 has-focus-visible:ring-ring/50",
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
              <span className="flex items-center justify-between gap-2">
                <span className="flex items-center gap-2">
                  <CategoryIcon category={PRESET_CATEGORY[name]} size="sm" />
                  <span className="text-sm font-medium">{preset.title}</span>
                </span>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {preset.blocks.length}{" "}
                  {preset.blocks.length === 1 ? "block" : "blocks"}
                </span>
              </span>
              <span className="line-clamp-2 text-xs leading-5 text-muted-foreground">
                {preset.description}
              </span>
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}
