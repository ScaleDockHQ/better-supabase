// #region recipe:org-switcher
"use client";

import { DbException } from "better-supabase";
import { useOrganizations } from "better-supabase/blocks/organizations/react";
import { CheckIcon, ChevronsUpDownIcon, PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { SidebarMenuButton } from "@/components/ui/sidebar";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { useErrorMessage } from "@/lib/use-error-message";

import type { OrganizationSummary } from "../organization-queries";

import { loadMyOrganizations } from "../organization-actions";
import { useRefreshSession } from "../use-refresh-session";
import { useRoleLabel } from "../use-role-label";
import { CreateOrganizationDialog } from "./create-organization-dialog";

function Mark({ name }: { name: string }) {
  return (
    <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sm font-semibold text-sidebar-primary-foreground">
      {name.slice(0, 1).toUpperCase()}
    </div>
  );
}

async function loadOrganizations(): Promise<readonly OrganizationSummary[]> {
  const result = await loadMyOrganizations({});

  if (!result.ok) {
    throw new DbException(result.error);
  }

  return result.data;
}

/**
 * The organization menu. The server renders it with its rows; switching
 * goes through `switch_organization`, refreshes the session for the new
 * tenant claim, then re-renders the server tree.
 */
export function OrganizationSwitcherMenu({
  initial,
  activeId: serverActiveId,
}: {
  initial: readonly OrganizationSummary[];
  activeId: string | null;
}) {
  const t = useExtracted("organization");
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const refreshSession = useRefreshSession();
  const [pending, startTransition] = useTransition();
  const [creating, setCreating] = useState(false);

  const { organizations, active, activeId, switchTo } = useOrganizations({
    load: loadOrganizations,
    initial,
    activeId: serverActiveId,
    schema: blockConfig.organizations.api,
    onSwitched: () => refreshSession("/"),
  });

  const choose = (organization: OrganizationSummary) => {
    startTransition(async () => {
      const result = await switchTo(organization.id);

      if (!result.ok) {
        toast.error(errorMessage(result.error));

        return;
      }

      toast.success(t("Switched to {name}", { name: organization.name }));
    });
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          disabled={pending}
          render={
            <SidebarMenuButton
              size="lg"
              className="data-popup-open:bg-sidebar-accent"
              aria-label={t("Switch organization")}
            />
          }
        >
          <Mark name={active?.name ?? "?"} />
          <div className="grid flex-1 text-left text-sm leading-tight">
            <span
              className="truncate font-medium"
              data-testid="organization-name"
            >
              {active?.name ?? t("No organization")}
            </span>
            <span className="truncate text-xs text-muted-foreground capitalize">
              {active ? active.plan : t("Create one to start")}
            </span>
          </div>
          <ChevronsUpDownIcon className="ml-auto" />
        </DropdownMenuTrigger>
        <DropdownMenuContent className="w-64" align="start" side="bottom">
          <DropdownMenuGroup>
            <DropdownMenuLabel>{t("Organizations")}</DropdownMenuLabel>
            {(organizations ?? initial).map((organization) => (
              <DropdownMenuItem
                key={organization.id}
                className="gap-2"
                onClick={() => {
                  if (organization.id !== activeId) {
                    choose(organization);
                  }
                }}
              >
                <Mark name={organization.name} />
                <div className="grid flex-1 leading-tight">
                  <span className="truncate">{organization.name}</span>
                  <span className="text-xs text-muted-foreground">
                    {roleLabel(organization.role)}
                  </span>
                </div>
                {organization.id === activeId ? <CheckIcon /> : null}
              </DropdownMenuItem>
            ))}
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onClick={() => {
              setCreating(true);
            }}
          >
            <PlusIcon />
            {t("Create organization")}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <CreateOrganizationDialog open={creating} onOpenChange={setCreating} />
    </>
  );
}
// #endregion recipe:org-switcher
