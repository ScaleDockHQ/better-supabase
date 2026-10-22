"use client";

import { useExtracted } from "next-intl";

import { DropdownMenuItem } from "@/components/ui/dropdown-menu";

import type { Later } from "../inbox-types";

/** The times a snooze ends or a scheduled reply goes out. */
export function LaterItems({ onSelect }: { onSelect: (later: Later) => void }) {
  const t = useExtracted("inbox");

  const items: readonly { readonly value: Later; readonly label: string }[] = [
    { value: "hour", label: t("In 1 hour") },
    { value: "tomorrow", label: t("Tomorrow") },
    { value: "week", label: t("Next week") },
  ];

  return items.map((item) => (
    <DropdownMenuItem
      key={item.value}
      onClick={() => {
        onSelect(item.value);
      }}
    >
      {item.label}
    </DropdownMenuItem>
  ));
}
