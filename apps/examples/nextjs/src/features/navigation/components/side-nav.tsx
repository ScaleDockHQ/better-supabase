"use client";

import type { LucideIcon } from "lucide-react";

import {
  ActivityIcon,
  IdCardIcon,
  BriefcaseIcon,
  ClockIcon,
  CalendarIcon,
  CalendarCheckIcon,
  CalendarRangeIcon,
  SquareKanbanIcon,
  TableIcon,
  ShieldCheckIcon,
  ShieldHalfIcon,
  ContactRoundIcon,
  KanbanIcon,
  SendIcon,
  MessageSquareTextIcon,
  FileTextIcon,
  StoreIcon,
  BoxesIcon,
  ReceiptIcon,
  FolderIcon,
  FolderKanbanIcon,
  NotebookTextIcon,
  ClipboardListIcon,
  PresentationIcon,
  LayoutTemplateIcon,
  FileUpIcon,
  Trash2Icon,
  CreditCardIcon,
  FlaskConicalIcon,
  BellIcon,
  CalendarClockIcon,
  CpuIcon,
  InboxIcon,
  MessagesSquareIcon,
  BotIcon,
  ChartColumnIcon,
  KeyRoundIcon,
  LibraryIcon,
  LayoutDashboardIcon,
  ListTodoIcon,
  ScrollTextIcon,
  SettingsIcon,
  UsersIcon,
  UsersRoundIcon,
  WaypointsIcon,
  ListFilterIcon,
  WorkflowIcon,
  RouteIcon,
  TruckIcon,
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

import type { NavId } from "../nav-items";

import { activeNavId, navItems } from "../nav-items";

const ICONS = {
  dashboard: LayoutDashboardIcon,
  myWork: ListTodoIcon,
  customers: UsersIcon,
  people: IdCardIcon,
  hiring: BriefcaseIcon,
  time: ClockIcon,
  calendar: CalendarIcon,
  availability: CalendarCheckIcon,
  work: SquareKanbanIcon,
  workGrid: TableIcon,
  projects: FolderKanbanIcon,
  approvals: ShieldCheckIcon,
  rules: ListFilterIcon,
  contacts: ContactRoundIcon,
  deals: KanbanIcon,
  sequences: SendIcon,
  quotes: FileTextIcon,
  shop: StoreIcon,
  inventory: BoxesIcon,
  orders: ReceiptIcon,
  dispatch: CalendarRangeIcon,
  myDay: RouteIcon,
  shipments: TruckIcon,
  drive: FolderIcon,
  documents: NotebookTextIcon,
  forms: ClipboardListIcon,
  courses: PresentationIcon,
  community: MessageSquareTextIcon,
  templates: LayoutTemplateIcon,
  imports: FileUpIcon,
  trash: Trash2Icon,
  metrics: ChartColumnIcon,
  compliance: ShieldHalfIcon,
  notifications: BellIcon,
  workflows: WorkflowIcon,
  workflowBuilder: WaypointsIcon,
  inbox: InboxIcon,
  chat: MessagesSquareIcon,
  assistant: BotIcon,
  knowledge: LibraryIcon,
  agentActivity: ActivityIcon,
  aiTasks: CalendarClockIcon,
  beta: FlaskConicalIcon,
  members: UsersRoundIcon,
  billing: CreditCardIcon,
  apiKeys: KeyRoundIcon,
  audit: ScrollTextIcon,
  aiProviders: CpuIcon,
  settings: SettingsIcon,
} satisfies Record<NavId, LucideIcon>;

function useNavLabel() {
  const t = useExtracted("navigation");

  return (id: NavId): string => {
    switch (id) {
      case "dashboard": {
        return t("Dashboard");
      }

      case "myWork": {
        return t("My work");
      }

      case "customers": {
        return t("Customers");
      }

      case "work": {
        return t("Work");
      }

      case "workGrid": {
        return t("Work grid");
      }

      case "projects": {
        return t("Projects");
      }

      case "approvals": {
        return t("Approvals");
      }

      case "rules": {
        return t("Rules");
      }

      case "people": {
        return t("People");
      }

      case "hiring": {
        return t("Hiring");
      }

      case "time": {
        return t("Time");
      }

      case "calendar": {
        return t("Calendar");
      }

      case "availability": {
        return t("Availability");
      }

      case "contacts": {
        return t("Contacts");
      }

      case "deals": {
        return t("Deals");
      }

      case "sequences": {
        return t("Sequences");
      }

      case "quotes": {
        return t("Quotes");
      }

      case "shop": {
        return t("Shop");
      }

      case "inventory": {
        return t("Inventory");
      }

      case "orders": {
        return t("Orders");
      }

      case "dispatch": {
        return t("Dispatch");
      }

      case "myDay": {
        return t("My day");
      }

      case "shipments": {
        return t("Shipments");
      }

      case "drive": {
        return t("Drive");
      }

      case "documents": {
        return t("Documents");
      }

      case "forms": {
        return t("Forms");
      }

      case "courses": {
        return t("Courses");
      }

      case "community": {
        return t("Community");
      }

      case "templates": {
        return t("Templates");
      }

      case "imports": {
        return t("Imports");
      }

      case "trash": {
        return t("Trash");
      }

      case "metrics": {
        return t("Metrics");
      }

      case "compliance": {
        return t("Compliance");
      }

      case "notifications": {
        return t("Notifications");
      }

      case "workflows": {
        return t("Workflows");
      }

      case "workflowBuilder": {
        return t("Workflow builder");
      }

      case "inbox": {
        return t("Inbox");
      }

      case "chat": {
        return t("Chat");
      }

      case "assistant": {
        return t("Assistant");
      }

      case "knowledge": {
        return t("Knowledge");
      }

      case "agentActivity": {
        return t("Agent activity");
      }

      case "aiTasks": {
        return t("AI tasks");
      }

      case "beta": {
        return t("Beta");
      }

      case "members": {
        return t("Members");
      }

      case "billing": {
        return t("Billing");
      }

      case "apiKeys": {
        return t("API keys");
      }

      case "audit": {
        return t("Audit log");
      }

      case "aiProviders": {
        return t("AI providers");
      }

      case "settings": {
        return t("Settings");
      }

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

        if (items.length === 0) {
          return null;
        }

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
