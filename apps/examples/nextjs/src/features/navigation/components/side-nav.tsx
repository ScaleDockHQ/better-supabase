import type { LucideIcon } from "lucide-react";

import {
  GiftIcon,
  GitForkIcon,
  ListOrderedIcon,
  TargetIcon,
  FileCodeIcon,
  GaugeIcon,
  NetworkIcon,
  TicketIcon,
  BookmarkIcon,
  StarIcon,
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
  TreePalmIcon,
  UserRoundCheckIcon,
  HourglassIcon,
  FileStackIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { getExtracted } from "next-intl/server";

import {
  SidebarGroup,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuSkeleton,
} from "@/components/ui/sidebar";

import type { NavArea as NavAreaId, NavId } from "../nav-items";

import { navAreas, navItems } from "../nav-items";
import { NavArea } from "./nav-area";
import { getNavLabel } from "./nav-label-server";
import { NavLink } from "./nav-link";

const ICONS = {
  dashboard: LayoutDashboardIcon,
  myWork: ListTodoIcon,
  customers: UsersIcon,
  people: IdCardIcon,
  hiring: BriefcaseIcon,
  leave: TreePalmIcon,
  onboarding: UserRoundCheckIcon,
  deadlines: HourglassIcon,
  documentTemplates: FileStackIcon,
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
  salesHome: LayoutDashboardIcon,
  pipelines: GitForkIcon,
  forecasts: CalendarClockIcon,
  segments: UsersRoundIcon,
  queues: ListOrderedIcon,
  scoring: TargetIcon,
  contracts: FileSignatureIcon,
  commissions: HandCoinsIcon,
  referrals: GiftIcon,
  customerSuccess: HeartPulseIcon,
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
  donations: HeartHandshakeIcon,
  passes: TicketIcon,
  checkoutSessions: BotIcon,
  collections: BookmarkIcon,
  reviews: StarIcon,
  warranty: ShieldCheckIcon,
  leases: KeyRoundIcon,
  assets: BoxesIcon,
  tills: CoinsIcon,
  shifts: CalendarDaysIcon,
  finance: LandmarkIcon,
  payables: ReceiptTextIcon,
  invoices: ReceiptIcon,
  expenses: WalletIcon,
  ledger: LibraryIcon,
  accountingBooks: NotebookTextIcon,
  billableTime: ClockIcon,
  recurring: CalendarClockIcon,
  tax: CoinsIcon,
  periods: CalendarRangeIcon,
  care: HeartHandshakeIcon,
  observations: HeartPulseIcon,
  medications: PillIcon,
  careAlerts: ShieldAlertIcon,
  prescriptions: FileSignatureIcon,
  carePlans: ClipboardPlusIcon,
  funding: HandCoinsIcon,
  notifications: BellIcon,
  workflows: WorkflowIcon,
  workflowRuns: WaypointsIcon,
  inbox: InboxIcon,
  chat: MessagesSquareIcon,
  assistant: BotIcon,
  knowledge: LibraryIcon,
  agentActivity: ActivityIcon,
  agents: NetworkIcon,
  prompts: FileCodeIcon,
  evals: ClipboardCheckIcon,
  guardrails: ShieldCheckIcon,
  aiUsage: GaugeIcon,
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

  const areaLabel = (area: NavAreaId): string => {
    switch (area) {
      case "home": {
        return t("Home");
      }

      case "sales": {
        return t("Sales");
      }

      case "commerce": {
        return t("Commerce");
      }

      case "operations": {
        return t("Operations");
      }

      case "finance": {
        return t("Finance");
      }

      case "people": {
        return t("People");
      }

      case "work": {
        return t("Work");
      }

      case "content": {
        return t("Content");
      }

      case "quality": {
        return t("Quality");
      }

      case "care": {
        return t("Care");
      }

      case "ai": {
        return t("AI");
      }

      case "admin": {
        return t("Admin");
      }

      default: {
        const unknown: never = area;

        return unknown;
      }
    }
  };

  return (
    <nav aria-label={t("Main")}>
      {navAreas.map((area) => {
        const items = navItems.filter(
          (item) => item.area === area && visible.includes(item.id),
        );

        if (items.length === 0) {
          return null;
        }

        return (
          <NavArea
            key={area}
            label={areaLabel(area)}
            ids={items.map((item) => item.id)}
          >
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
          </NavArea>
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
