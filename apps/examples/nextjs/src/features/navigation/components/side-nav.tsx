"use client";

import {
  CreditCardIcon,
  FlaskConicalIcon,
  BellIcon,
  KeyRoundIcon,
  LayoutDashboardIcon,
  type LucideIcon,
  ScrollTextIcon,
  SettingsIcon,
  UsersIcon,
  UsersRoundIcon,
  WorkflowIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";

import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSkeleton,
} from "@/components/ui/sidebar";
import { Link, usePathname } from "@/i18n/navigation";

import { type NavId, activeNavId, navItems } from "../nav-items";

const ICONS = {
  dashboard: LayoutDashboardIcon,
  customers: UsersIcon,
  notifications: BellIcon,
  workflows: WorkflowIcon,
  beta: FlaskConicalIcon,
  members: UsersRoundIcon,
  billing: CreditCardIcon,
  apiKeys: KeyRoundIcon,
  audit: ScrollTextIcon,
  settings: SettingsIcon,
} satisfies Record<NavId, LucideIcon>;

function useNavLabel() {
  const t = useExtracted("navigation");
  return (id: NavId): string => {
    switch (id) {
      case "dashboard":
        return t("Dashboard");
      case "customers":
        return t("Customers");
      case "notifications":
        return t("Notifications");
      case "workflows":
        return t("Workflows");
      case "beta":
        return t("Beta");
      case "members":
        return t("Members");
      case "billing":
        return t("Billing");
      case "apiKeys":
        return t("API keys");
      case "audit":
        return t("Audit log");
      case "settings":
        return t("Settings");
      default: {
        const unknown: never = id;
        return unknown;
      }
    }
  };
}

export function SideNav({ visible }: { visible: readonly NavId[] }) {
  const t = useExtracted("navigation");
  const label = useNavLabel();
  const active = activeNavId(usePathname());
  const groups = [
    { id: "workspace", label: t("Workspace") },
    { id: "organization", label: t("Organization") },
  ] as const;
  return (
    <nav aria-label={t("Main")}>
      {groups.map((group) => {
        const items = navItems.filter(
          (item) => item.group === group.id && visible.includes(item.id),
        );
        if (items.length === 0) return null;
        return (
          <SidebarGroup key={group.id}>
            <SidebarGroupLabel>{group.label}</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {items.map((item) => {
                  const Icon = ICONS[item.id];
                  return (
                    <SidebarMenuItem key={item.id}>
                      <SidebarMenuButton
                        isActive={active === item.id}
                        tooltip={label(item.id)}
                        render={
                          <Link
                            href={item.href}
                            aria-current={
                              active === item.id ? "page" : undefined
                            }
                          />
                        }
                      >
                        <Icon />
                        <span>{label(item.id)}</span>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  );
                })}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        );
      })}
    </nav>
  );
}

const SKELETON_WIDTHS = ["60%", "80%", "55%", "70%", "85%", "65%"];

export function SideNavSkeleton() {
  const t = useExtracted("navigation");
  return (
    <nav aria-label={t("Main")} aria-busy="true">
      <SidebarGroup>
        <SidebarMenu>
          {SKELETON_WIDTHS.map((width) => (
            <SidebarMenuItem key={width}>
              <SidebarMenuSkeleton showIcon width={width} />
            </SidebarMenuItem>
          ))}
        </SidebarMenu>
      </SidebarGroup>
    </nav>
  );
}
