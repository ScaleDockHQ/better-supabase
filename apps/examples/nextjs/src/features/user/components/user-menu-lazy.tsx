"use client";

import { ChevronsUpDownIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { lazy } from "react";

import type { Role } from "@/lib/claims";

import { LazyOnIntent } from "@/components/lazy-on-intent";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { SidebarMenuButton } from "@/components/ui/sidebar";
import { useRoleLabel } from "@/features/organization/use-role-label";
import { initials } from "@/lib/initials";

const UserMenuDropdown = lazy(() =>
  import("./user-menu-dropdown").then((mod) => ({
    default: mod.UserMenuDropdown,
  })),
);

interface UserMenuProps {
  readonly name: string | null;
  readonly email: string | null;
  readonly avatarUrl: string | null;
  readonly role: Role | null;
}

/**
 * The account menu's closed trigger. Base UI's menu, its submenus and the
 * session and theme hooks load on the first hover, focus or click.
 */
export function UserMenuLazy(props: UserMenuProps) {
  const t = useExtracted("user");
  const roleLabel = useRoleLabel();

  return (
    <LazyOnIntent
      renderTrigger={(handlers) => (
        <SidebarMenuButton
          size="lg"
          aria-label={t("Account menu")}
          aria-haspopup="menu"
          {...handlers}
        >
          <Avatar className="size-8 rounded-lg">
            {props.avatarUrl ? (
              <AvatarImage src={props.avatarUrl} alt="" />
            ) : null}
            <AvatarFallback className="rounded-lg">
              {initials(props.name, props.email)}
            </AvatarFallback>
          </Avatar>
          <div className="grid flex-1 text-left text-sm leading-tight">
            <span className="truncate font-medium">
              {props.name ?? props.email}
            </span>
            <span
              className="truncate text-xs text-muted-foreground"
              data-testid="role"
            >
              {props.role ? roleLabel(props.role) : t("No role")}
            </span>
          </div>
          <ChevronsUpDownIcon className="ml-auto size-4" />
        </SidebarMenuButton>
      )}
    >
      <UserMenuDropdown {...props} />
    </LazyOnIntent>
  );
}
