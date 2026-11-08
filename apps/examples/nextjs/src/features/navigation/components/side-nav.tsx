import type { LucideIcon } from "lucide-react";

import {
  BanknoteIcon,
  ActivityIcon,
  HeartPulseIcon,
  HeartHandshakeIcon,
  BadgeCheckIcon,
  IdCardIcon,
  BriefcaseIcon,
  ClockIcon,
  CalendarIcon,
  CalendarCheckIcon,
  CalendarRangeIcon,
  CalendarDaysIcon,
  SquareKanbanIcon,
  TableIcon,
  ShieldCheckIcon,
  ShieldHalfIcon,
  FileSignatureIcon,
  ShieldAlertIcon,
  LandmarkIcon,
  ClipboardPlusIcon,
  ContactRoundIcon,
  KanbanIcon,
  SendIcon,
  MessageSquareTextIcon,
  FileTextIcon,
  StoreIcon,
  FactoryIcon,
  BoxesIcon,
  ReceiptIcon,
  FolderIcon,
  FolderKanbanIcon,
  NotebookTextIcon,
  ClipboardListIcon,
  HandCoinsIcon,
  PillIcon,
  PresentationIcon,
  LayoutTemplateIcon,
  FileUpIcon,
  FileWarningIcon,
  ClipboardCheckIcon,
  GavelIcon,
  WrenchIcon,
  ImagesIcon,
  AwardIcon,
  Trash2Icon,
  CreditCardIcon,
  FileQuestionMarkIcon,
  FlaskConicalIcon,
  GridIcon,
  BellIcon,
  CalendarClockIcon,
  CpuIcon,
  InboxIcon,
  MessagesSquareIcon,
  BotIcon,
  ChartColumnIcon,
  CoinsIcon,
  KeyRoundIcon,
  LibraryIcon,
  LayoutDashboardIcon,
  ListTodoIcon,
  ScrollTextIcon,
  SettingsIcon,
  UsersIcon,
  GroupIcon,
  ShieldIcon,
  UsersRoundIcon,
  WaypointsIcon,
  ListFilterIcon,
  WorkflowIcon,
  RouteIcon,
  TruckIcon,
  PackageSearchIcon,
  ReceiptTextIcon,
  WalletIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { getExtracted } from "next-intl/server";

import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuSkeleton,
} from "@/components/ui/sidebar";

import type { NavId } from "../nav-items";

import { navItems } from "../nav-items";
import { getNavLabel } from "./nav-label-server";
import { NavLink } from "./nav-link";

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
  manufacturing: FactoryIcon,
  production: PackageSearchIcon,
  banking: BanknoteIcon,
  legalEntities: LandmarkIcon,
  payrollExport: WalletIcon,
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
  qualifications: BadgeCheckIcon,
  risks: ShieldAlertIcon,
  cases: FileWarningIcon,
  inspections: ClipboardCheckIcon,
  meetings: GavelIcon,
  maintenance: WrenchIcon,
  dam: ImagesIcon,
  lims: FlaskConicalIcon,
  appraisals: AwardIcon,
  warehouse: ClipboardListIcon,
  rfqs: FileQuestionMarkIcon,
  tills: CoinsIcon,
  shifts: CalendarDaysIcon,
  finance: LandmarkIcon,
  payables: ReceiptTextIcon,
  care: HeartHandshakeIcon,
  observations: HeartPulseIcon,
  medications: PillIcon,
  careAlerts: ShieldAlertIcon,
  prescriptions: FileSignatureIcon,
  carePlans: ClipboardPlusIcon,
  funding: HandCoinsIcon,
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
  islands: GridIcon,
  members: UsersRoundIcon,
  teams: GroupIcon,
  roles: ShieldIcon,
  billing: CreditCardIcon,
  apiKeys: KeyRoundIcon,
  audit: ScrollTextIcon,
  aiProviders: CpuIcon,
  settings: SettingsIcon,
} satisfies Record<NavId, LucideIcon>;

export async function SideNav({ visible }: { visible: readonly NavId[] }) {
  const t = await getExtracted("navigation");
  const label = await getNavLabel();

  const groups = [
    { id: "workspace", label: t("Workspace") },
    { id: "quality", label: t("Quality") },
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
                      <NavLink
                        id={item.id}
                        href={item.href}
                        label={label(item.id)}
                      >
                        <Icon />
                      </NavLink>
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
