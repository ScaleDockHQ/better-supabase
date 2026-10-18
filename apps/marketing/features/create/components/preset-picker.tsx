import type { ReactElement } from "react";

import {
  isPresetName,
  PRESET_GROUPS,
  PRESET_NAMES,
  type PresetName,
  PRESETS,
} from "better-supabase/preset";
import { LayoutTemplateIcon, SlidersHorizontalIcon } from "lucide-react";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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
import { isEmptyDesign } from "@/lib/design";
import {
  DESIGN_TEMPLATES,
  type DesignTemplate,
  templatePreset,
  templateTables,
} from "@/lib/design-templates";

import { PRESET_CATEGORY } from "../preset-categories";
import { useDesign } from "./design-provider";

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
 * longer match any preset, and the select then shows Custom. The label is
 * visually hidden because the Preset section's trigger names it.
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
    <div className="flex flex-col">
      <label htmlFor={id} className="sr-only">
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

function TemplateOption({
  template,
  onPick,
}: {
  template: DesignTemplate;
  onPick: (template: DesignTemplate) => void;
}): ReactElement {
  return (
    <li>
      <button
        type="button"
        className="flex w-full items-start gap-3 px-3 py-3 text-left transition-colors hover:bg-muted/50 focus-visible:bg-muted/50 focus-visible:outline-none"
        onClick={() => {
          onPick(template);
        }}
      >
        <CategoryIcon category={PRESET_CATEGORY[template.preset]} size="sm" />
        <span className="flex min-w-0 flex-1 flex-col gap-1">
          <span className="flex flex-wrap items-baseline gap-2">
            <span className="text-sm font-medium">{template.title}</span>
            <span className="text-xs text-muted-foreground">
              {PRESETS[template.preset].title} preset
            </span>
          </span>
          <span className="text-xs text-muted-foreground">
            {template.description}
          </span>
          <span className="flex flex-wrap gap-1">
            {templateTables(template).map((table) => (
              <Badge key={table} variant="outline" className="font-mono">
                {table}
              </Badge>
            ))}
          </span>
        </span>
      </button>
    </li>
  );
}

/**
 * "Start from a template": a dialog of starting designs. Picking one sets
 * its preset and blocks and replaces the app tables as one undo step.
 */
export function TemplatePicker(): ReactElement {
  const { state, actions } = useDesign();
  const [open, setOpen] = useState(false);
  const replaces = !isEmptyDesign(state.design);

  const pick = (template: DesignTemplate): void => {
    actions.startFrom(
      (current) => templatePreset(current, template),
      template.design,
    );
    setOpen(false);
    toast(`Started from ${template.title}`, {
      action: { label: "Undo", onClick: actions.undo },
    });
  };

  return (
    <>
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="w-full"
        onClick={() => {
          setOpen(true);
        }}
      >
        <LayoutTemplateIcon aria-hidden="true" />
        Start from a template
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[calc(100svh-2rem)] grid-rows-[auto_minmax(0,1fr)] sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Start from a template</DialogTitle>
            <DialogDescription>
              {replaces
                ? "A template sets the preset and replaces the app tables on the canvas. Undo brings them back."
                : "A template sets the preset and adds app tables, relations and record features you can edit."}
            </DialogDescription>
          </DialogHeader>
          <ul className="min-h-0 divide-y divide-border overflow-y-auto border-y border-border">
            {DESIGN_TEMPLATES.map((template) => (
              <TemplateOption
                key={template.id}
                template={template}
                onPick={pick}
              />
            ))}
          </ul>
        </DialogContent>
      </Dialog>
    </>
  );
}
