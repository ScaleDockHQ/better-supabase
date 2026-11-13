"use client";

import { DbException } from "better-supabase";
import { useErrorMessage } from "better-supabase/react";
import { Building2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";

import type { OrganizationSummary } from "@/features/organization/organization-queries";

import {
  CommandGroup,
  CommandItem,
  CommandSeparator,
} from "@/components/ui/command";
import { loadMyOrganizations } from "@/features/organization/organization-actions";
import { useRefreshSession } from "@/features/organization/use-refresh-session";
import { useOrganizations } from "@/hooks/use-organizations";
import { organizationsConfig } from "@/lib/supabase/blocks/slices";
import { toast } from "@/lib/toast";

async function loadOrganizations(): Promise<readonly OrganizationSummary[]> {
  const result = await loadMyOrganizations({});

  if (!result.ok) {
    throw new DbException(result.error);
  }

  return result.data;
}

/**
 * The "Switch organization" group: the organizations the caller belongs to,
 * other than the active one, filtered by what was typed. It mounts with the
 * open palette and loads the list through the same server action as the sidebar
 * menu.
 */
export function OrganizationCommands({
  query,
  onSwitched,
}: {
  query: string;
  onSwitched: () => void;
}) {
  const t = useExtracted("search");
  const errorMessage = useErrorMessage();
  const refreshSession = useRefreshSession();
  const [pending, startTransition] = useTransition();

  const { organizations, activeId, switchTo } = useOrganizations({
    load: loadOrganizations,
    schema: organizationsConfig.api,
    onSwitched: () => refreshSession("/"),
  });

  const others = (organizations ?? []).filter(
    (organization) =>
      organization.id !== activeId &&
      (query === "" ||
        `${t("Switch organization")} ${organization.name}`
          .toLowerCase()
          .includes(query.toLowerCase())),
  );

  if (others.length === 0) {
    return null;
  }

  return (
    <>
      <CommandSeparator />
      <CommandGroup heading={t("Switch organization")}>
        {others.map((organization) => (
          <CommandItem
            key={organization.id}
            value={`organization:${organization.id}`}
            disabled={pending}
            onSelect={() => {
              startTransition(async () => {
                const result = await switchTo(organization.id);

                if (!result.ok) {
                  toast.error(errorMessage(result.error));

                  return;
                }

                onSwitched();
                toast.success(
                  t("Switched to {name}", { name: organization.name }),
                );
              });
            }}
          >
            <Building2Icon />
            {organization.name}
          </CommandItem>
        ))}
      </CommandGroup>
    </>
  );
}
