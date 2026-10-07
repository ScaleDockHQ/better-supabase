"use client";

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
import { useErrorMessage } from "@/lib/use-error-message";

import type { OrganizationSummary } from "../organization-queries";

import { switchOrganization } from "../organization-actions";
import { useRefreshSession } from "../use-refresh-session";
import { useRoleLabel } from "../use-role-label";
import { CreateOrganizationDialog } from "./create-organization-dialog";

function Mark({ name }: { name: string }) {
  return (
    <div className="bg-sidebar-primary text-sidebar-primary-foreground flex aspect-square size-8 items-center justify-center rounded-lg text-sm font-semibold">
      {name.slice(0, 1).toUpperCase()}
    </div>
  );
}

export function OrganizationSwitcherMenu({
  organizations,
  activeId,
}: {
  organizations: readonly OrganizationSummary[];
  activeId: string | null;
}) {
  const t = useExtracted("organization");
  const roleLabel = useRoleLabel();
  const errorMessage = useErrorMessage();
  const refreshSession = useRefreshSession();
  const [pending, startTransition] = useTransition();
  const [creating, setCreating] = useState(false);
  const active = organizations.find(
    (organization) => organization.id === activeId,
  );

  const switchTo = (organization: OrganizationSummary) => {
    startTransition(async () => {
      const result = await switchOrganization({
        organizationId: organization.id,
      });
      if (!result.ok) {
        toast.error(errorMessage(result.error));
        return;
      }
      await refreshSession("/");
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
            <span className="text-muted-foreground truncate text-xs capitalize">
              {active ? active.plan : t("Create one to start")}
            </span>
          </div>
          <ChevronsUpDownIcon className="ml-auto" />
        </DropdownMenuTrigger>
        <DropdownMenuContent className="w-64" align="start" side="bottom">
          <DropdownMenuGroup>
            <DropdownMenuLabel>{t("Organizations")}</DropdownMenuLabel>
            {organizations.map((organization) => (
              <DropdownMenuItem
                key={organization.id}
                className="gap-2"
                onClick={() => {
                  if (organization.id !== activeId) switchTo(organization);
                }}
              >
                <Mark name={organization.name} />
                <div className="grid flex-1 leading-tight">
                  <span className="truncate">{organization.name}</span>
                  <span className="text-muted-foreground text-xs">
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
