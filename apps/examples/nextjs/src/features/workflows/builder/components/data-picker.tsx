"use client";

import { BracesIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

import type { PickerGroup } from "../editor-model";

import { templateMarker } from "../config-templates";

/**
 * Lists what the node can read (the run's input and the nodes before it) and
 * hands back the `{{ path }}` marker of the pick, which the steps fill in when
 * the run reaches the node.
 */
export function DataPicker({
  groups,
  label,
  onPick,
}: {
  groups: readonly PickerGroup[];
  /** The field's name, for the button's accessible name. */
  label: string;
  onPick: (marker: string) => void;
}) {
  const t = useExtracted("workflows");

  return (
    <Popover>
      <PopoverTrigger
        render={
          <Button
            type="button"
            variant="ghost"
            size="icon-xs"
            aria-label={t("Insert data into {field}", { field: label })}
          />
        }
      >
        <BracesIcon />
      </PopoverTrigger>
      <PopoverContent align="end" className="w-72 p-0">
        <Command>
          <CommandInput placeholder={t("Find a field")} />
          <CommandList>
            <CommandEmpty>{t("Nothing to pick yet")}</CommandEmpty>
            {groups.map((group) => (
              <CommandGroup key={group.id} heading={group.label}>
                {group.paths.map((path) => (
                  <CommandItem
                    key={path}
                    value={path}
                    onSelect={() => {
                      onPick(templateMarker(path));
                    }}
                  >
                    <span className="truncate font-mono text-xs">{path}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            ))}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
