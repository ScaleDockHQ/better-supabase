"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useOptimistic, useTransition } from "react";
import { toast } from "sonner";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import { setCustomerOwnerTeam } from "../customer-actions";

const NO_TEAM = "none";

/**
 * Picks the team from the teams block that owns a customer. The choice shows at
 * once and rolls back when the database refuses it.
 */
export function OwnerTeamSelect({
  customerId,
  ownerTeamId,
  teams,
  disabled,
}: {
  customerId: string;
  ownerTeamId: string | null;
  teams: readonly { id: string; name: string }[];
  disabled: boolean;
}) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();
  const [owner, setOwner] = useOptimistic(ownerTeamId ?? NO_TEAM);
  const [pending, startTransition] = useTransition();

  const save = useAction(setCustomerOwnerTeam, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const items = [
    { value: NO_TEAM, label: t("No owner team") },
    ...teams.map((team) => ({ value: team.id, label: team.name })),
  ];

  return (
    <Select
      value={owner}
      items={items}
      disabled={disabled || pending}
      onValueChange={(value) => {
        const picked = items.find((item) => item.value === value);

        if (!picked) {
          return;
        }

        startTransition(async () => {
          setOwner(picked.value);
          await save.run({
            customerId,
            teamId: picked.value === NO_TEAM ? null : picked.value,
          });
        });
      }}
    >
      <SelectTrigger
        className="w-full"
        aria-label={t("Owner team")}
        data-testid="owner-team"
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
