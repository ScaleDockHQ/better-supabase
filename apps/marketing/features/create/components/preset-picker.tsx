import type { ReactElement } from "react";

import {
  isPresetName,
  PRESET_GROUPS,
  PRESET_NAMES,
  type PresetName,
  PRESETS,
} from "better-supabase/preset";
import { SlidersHorizontalIcon } from "lucide-react";
import { useId } from "react";

import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { CUSTOM_PRESET, PRESET_ITEMS } from "@/lib/create-options";

import { PRESET_CATEGORY } from "../preset-categories";

function PresetLabel({ value }: { value: string }): ReactElement {
  if (!isPresetName(value)) {
    return (
      <>
        <SlidersHorizontalIcon
          aria-hidden="true"
          className="size-4 text-muted-foreground"
        />
        {CUSTOM_PRESET.label}
      </>
    );
  }

  return (
    <>
      <CategoryIcon category={PRESET_CATEGORY[value]} size="sm" />
      {PRESETS[value].title}
    </>
  );
}

const GROUPS = Object.values(PRESET_GROUPS).map((label) => ({
  label,
  names: PRESET_NAMES.filter(
    (name) => PRESET_GROUPS[PRESETS[name].group] === label,
  ),
}));

function blockCount(name: PresetName): string {
  const count = PRESETS[name].blocks.length;

  return `${count} ${count === 1 ? "block" : "blocks"}`;
}

/**
 * The named presets as a select. `selected` is undefined once the blocks no
 * longer match any preset, and the select then shows Custom.
 */
export function PresetPicker({
  selected,
  onSelect,
}: {
  selected: PresetName | undefined;
  onSelect: (name: PresetName) => void;
}): ReactElement {
  const id = useId();

  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-sm font-medium">
        Preset
      </label>
      <Select
        value={selected ?? CUSTOM_PRESET.value}
        items={PRESET_ITEMS}
        onValueChange={(next) => {
          if (next !== null && isPresetName(next)) {
            onSelect(next);
          }
        }}
      >
        <SelectTrigger id={id} className="w-full">
          <SelectValue>
            {(value: string) => <PresetLabel value={value} />}
          </SelectValue>
        </SelectTrigger>
        <SelectContent>
          {GROUPS.map(({ label, names }) => (
            <SelectGroup key={label}>
              <SelectLabel>{label}</SelectLabel>
              {names.map((name) => (
                <SelectItem key={name} value={name} label={PRESETS[name].title}>
                  <span className="flex min-w-0 items-start gap-2">
                    <CategoryIcon category={PRESET_CATEGORY[name]} size="sm" />
                    <span className="flex min-w-0 flex-col gap-0.5">
                      <span className="flex items-baseline gap-2">
                        <span className="font-medium">
                          {PRESETS[name].title}
                        </span>
                        <span className="text-xs text-muted-foreground tabular-nums">
                          {blockCount(name)}
                        </span>
                      </span>
                      <span className="max-w-64 text-xs whitespace-normal text-muted-foreground">
                        {PRESETS[name].description}
                      </span>
                    </span>
                  </span>
                </SelectItem>
              ))}
            </SelectGroup>
          ))}
          <SelectSeparator />
          <SelectItem
            value={CUSTOM_PRESET.value}
            label={CUSTOM_PRESET.label}
            disabled
          >
            <span className="flex min-w-0 items-start gap-2">
              <SlidersHorizontalIcon
                aria-hidden="true"
                className="mt-0.5 size-4 text-muted-foreground"
              />
              <span className="flex min-w-0 flex-col gap-0.5">
                <span className="font-medium">{CUSTOM_PRESET.label}</span>
                <span className="max-w-64 text-xs whitespace-normal text-muted-foreground">
                  {CUSTOM_PRESET.description}
                </span>
              </span>
            </span>
          </SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}
