"use client";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export interface SelectOption {
  readonly value: string;
  readonly label: string;
}

/** A select that submits `name` with its form. */
export function FormSelect({
  id,
  name,
  items,
  value,
  defaultValue,
  onValueChange,
  size = "default",
  label,
}: {
  id?: string;
  name: string;
  items: readonly SelectOption[];
  value?: string;
  defaultValue?: string;
  onValueChange?: (value: string) => void;
  size?: "sm" | "default";
  label?: string;
}) {
  return (
    <Select
      name={name}
      items={items}
      {...(value === undefined ? {} : { value })}
      {...(defaultValue === undefined ? {} : { defaultValue })}
      onValueChange={(next) => {
        if (next !== null) {
          onValueChange?.(next);
        }
      }}
    >
      <SelectTrigger
        size={size}
        className="w-full"
        {...(id === undefined ? {} : { id })}
        {...(label === undefined ? {} : { "aria-label": label })}
      >
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {items.map((item) => (
          <SelectItem key={item.value} value={item.value}>
            {item.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
