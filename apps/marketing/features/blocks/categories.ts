import {
  BellIcon,
  BotIcon,
  Building2Icon,
  CalendarDaysIcon,
  CodeXmlIcon,
  CreditCardIcon,
  DatabaseIcon,
  FileTextIcon,
  HandshakeIcon,
  KanbanIcon,
  type LucideIcon,
  MessagesSquareIcon,
  RocketIcon,
  ScaleIcon,
  ShieldCheckIcon,
  TableIcon,
  UsersIcon,
  WorkflowIcon,
} from "lucide-react";

import { RECIPE_CATEGORY_NAMES } from "../../lib/recipe-filter";

/** The catalog categories, in the order `catalog.json` lists them. */
export const CATEGORY_NAMES = [
  "Identity & access",
  "Tenancy & accounts",
  "Collaboration",
  "Notifications & messaging",
  "Growth & engagement",
  "CRM & sales",
  "Work management",
  "People",
  "Billing & commerce",
  "Scheduling",
  "Content & files",
  "AI",
  "Automation",
  "Developer platform",
  "Admin & compliance",
  "Database primitives",
] as const;

export type CategoryName = (typeof CATEGORY_NAMES)[number];

export type StyledCategoryName =
  | CategoryName
  | (typeof RECIPE_CATEGORY_NAMES)[number];

/**
 * How a category looks wherever it appears. The hue marks categorical identity
 * only; every class is a literal so Tailwind finds it, and each light class has
 * its `dark:` pair.
 */
export interface CategoryStyle {
  readonly name: StyledCategoryName;
  readonly slug: string;
  readonly icon: LucideIcon;
  /** One sentence for the category heading and the front page tile. */
  readonly summary: string;
  /** Text and icons on `background` or `tint`: 4.5:1 or more in both themes. */
  readonly text: string;
  /** The preview surface behind a block's mini UI. */
  readonly tint: string;
  /** A small solid mark: dots, bars, avatars in the previews. */
  readonly solid: string;
  /** A soft fill for chips and bars in the previews. */
  readonly soft: string;
  /** The border of a tinted surface. */
  readonly ring: string;
}

const STYLES = {
  "Identity & access": {
    slug: "identity-access",
    icon: ShieldCheckIcon,
    summary:
      "Sign-in, MFA, sessions, SSO, grants and access requests: who a user is and what they may do.",
    text: "text-sky-700 dark:text-sky-300",
    tint: "bg-sky-50 dark:bg-sky-950/40",
    solid: "bg-sky-500 dark:bg-sky-400",
    soft: "bg-sky-500/15 dark:bg-sky-400/20",
    ring: "border-sky-200 dark:border-sky-900",
  },
  "Tenancy & accounts": {
    slug: "tenancy-accounts",
    icon: Building2Icon,
    summary:
      "Tenants, organizations, teams, profiles, settings and workspace URLs.",
    text: "text-teal-700 dark:text-teal-300",
    tint: "bg-teal-50 dark:bg-teal-950/40",
    solid: "bg-teal-500 dark:bg-teal-400",
    soft: "bg-teal-500/15 dark:bg-teal-400/20",
    ring: "border-teal-200 dark:border-teal-900",
  },
  Collaboration: {
    slug: "collaboration",
    icon: MessagesSquareIcon,
    summary: "Comments, reactions, attachments and share links on any record.",
    text: "text-pink-700 dark:text-pink-300",
    tint: "bg-pink-50 dark:bg-pink-950/40",
    solid: "bg-pink-500 dark:bg-pink-400",
    soft: "bg-pink-500/15 dark:bg-pink-400/20",
    ring: "border-pink-200 dark:border-pink-900",
  },
  "Notifications & messaging": {
    slug: "notifications-messaging",
    icon: BellIcon,
    summary: "In-app notifications, push and a shared inbox with threads.",
    text: "text-rose-700 dark:text-rose-300",
    tint: "bg-rose-50 dark:bg-rose-950/40",
    solid: "bg-rose-500 dark:bg-rose-400",
    soft: "bg-rose-500/15 dark:bg-rose-400/20",
    ring: "border-rose-200 dark:border-rose-900",
  },
  "Growth & engagement": {
    slug: "growth-engagement",
    icon: RocketIcon,
    summary:
      "Onboarding checklists, waitlists, announcements and feature flags.",
    text: "text-lime-700 dark:text-lime-300",
    tint: "bg-lime-50 dark:bg-lime-950/40",
    solid: "bg-lime-500 dark:bg-lime-400",
    soft: "bg-lime-500/15 dark:bg-lime-400/20",
    ring: "border-lime-200 dark:border-lime-900",
  },
  "CRM & sales": {
    slug: "crm-sales",
    icon: HandshakeIcon,
    summary: "Parties, engagements, deals, quotes and targets.",
    text: "text-blue-700 dark:text-blue-300",
    tint: "bg-blue-50 dark:bg-blue-950/40",
    solid: "bg-blue-500 dark:bg-blue-400",
    soft: "bg-blue-500/15 dark:bg-blue-400/20",
    ring: "border-blue-200 dark:border-blue-900",
  },
  "Work management": {
    slug: "work-management",
    icon: KanbanIcon,
    summary:
      "Work items, pipelines, state machines, approvals, SLAs, tags, custom fields, saved views and search.",
    text: "text-orange-700 dark:text-orange-300",
    tint: "bg-orange-50 dark:bg-orange-950/40",
    solid: "bg-orange-500 dark:bg-orange-400",
    soft: "bg-orange-500/15 dark:bg-orange-400/20",
    ring: "border-orange-200 dark:border-orange-900",
  },
  People: {
    slug: "people",
    icon: UsersIcon,
    summary: "Employees, hiring and time tracking.",
    text: "text-yellow-800 dark:text-yellow-300",
    tint: "bg-yellow-50 dark:bg-yellow-950/40",
    solid: "bg-yellow-500 dark:bg-yellow-400",
    soft: "bg-yellow-500/15 dark:bg-yellow-400/20",
    ring: "border-yellow-200 dark:border-yellow-900",
  },
  "Billing & commerce": {
    slug: "billing-commerce",
    icon: CreditCardIcon,
    summary:
      "Billing, entitlements, usage, invoices, a product catalog, inventory, orders and promotions.",
    text: "text-emerald-700 dark:text-emerald-300",
    tint: "bg-emerald-50 dark:bg-emerald-950/40",
    solid: "bg-emerald-500 dark:bg-emerald-400",
    soft: "bg-emerald-500/15 dark:bg-emerald-400/20",
    ring: "border-emerald-200 dark:border-emerald-900",
  },
  Scheduling: {
    slug: "scheduling",
    icon: CalendarDaysIcon,
    summary: "Calendars, bookings and reminders.",
    text: "text-cyan-700 dark:text-cyan-300",
    tint: "bg-cyan-50 dark:bg-cyan-950/40",
    solid: "bg-cyan-500 dark:bg-cyan-400",
    soft: "bg-cyan-500/15 dark:bg-cyan-400/20",
    ring: "border-cyan-200 dark:border-cyan-900",
  },
  "Content & files": {
    slug: "content-files",
    icon: FileTextIcon,
    summary:
      "Documents, a drive, forms, signatures, templates, versions, trash and imports.",
    text: "text-fuchsia-700 dark:text-fuchsia-300",
    tint: "bg-fuchsia-50 dark:bg-fuchsia-950/40",
    solid: "bg-fuchsia-500 dark:bg-fuchsia-400",
    soft: "bg-fuchsia-500/15 dark:bg-fuchsia-400/20",
    ring: "border-fuchsia-200 dark:border-fuchsia-900",
  },
  AI: {
    slug: "ai",
    icon: BotIcon,
    summary:
      "Chat, files, knowledge, memory, agents, background tasks, providers and vector search.",
    text: "text-violet-700 dark:text-violet-300",
    tint: "bg-violet-50 dark:bg-violet-950/40",
    solid: "bg-violet-500 dark:bg-violet-400",
    soft: "bg-violet-500/15 dark:bg-violet-400/20",
    ring: "border-violet-200 dark:border-violet-900",
  },
  Automation: {
    slug: "automation",
    icon: WorkflowIcon,
    summary:
      "Workflows and their builder, jobs, the outbox, streams and connectors.",
    text: "text-amber-700 dark:text-amber-300",
    tint: "bg-amber-50 dark:bg-amber-950/40",
    solid: "bg-amber-500 dark:bg-amber-400",
    soft: "bg-amber-500/15 dark:bg-amber-400/20",
    ring: "border-amber-200 dark:border-amber-900",
  },
  "Developer platform": {
    slug: "developer-platform",
    icon: CodeXmlIcon,
    summary:
      "API keys, webhooks, service principals, signing keys, credentials and rate limits.",
    text: "text-indigo-700 dark:text-indigo-300",
    tint: "bg-indigo-50 dark:bg-indigo-950/40",
    solid: "bg-indigo-500 dark:bg-indigo-400",
    soft: "bg-indigo-500/15 dark:bg-indigo-400/20",
    ring: "border-indigo-200 dark:border-indigo-900",
  },
  "Admin & compliance": {
    slug: "admin-compliance",
    icon: ScaleIcon,
    summary:
      "The audit log, data export and deletion, metrics and support sessions.",
    text: "text-purple-700 dark:text-purple-300",
    tint: "bg-purple-50 dark:bg-purple-950/40",
    solid: "bg-purple-500 dark:bg-purple-400",
    soft: "bg-purple-500/15 dark:bg-purple-400/20",
    ring: "border-purple-200 dark:border-purple-900",
  },
  "Database primitives": {
    slug: "database-primitives",
    icon: DatabaseIcon,
    summary:
      "RLS checks, pgTAP, JSON schemas, number sequences, ranks, read sets and realtime tables.",
    text: "text-slate-700 dark:text-slate-300",
    tint: "bg-slate-50 dark:bg-slate-950/40",
    solid: "bg-slate-500 dark:bg-slate-400",
    soft: "bg-slate-500/15 dark:bg-slate-400/20",
    ring: "border-slate-200 dark:border-slate-900",
  },
  "App tables": {
    slug: "app-tables",
    icon: TableIcon,
    summary:
      "Grids, forms, record pages, boards, calendars and timelines over your own tables.",
    text: "text-stone-700 dark:text-stone-300",
    tint: "bg-stone-50 dark:bg-stone-950/40",
    solid: "bg-stone-500 dark:bg-stone-400",
    soft: "bg-stone-500/15 dark:bg-stone-400/20",
    ring: "border-stone-200 dark:border-stone-900",
  },
} satisfies Record<StyledCategoryName, Omit<CategoryStyle, "name">>;

function isCategoryName(name: string): name is StyledCategoryName {
  return [...CATEGORY_NAMES, ...RECIPE_CATEGORY_NAMES].some(
    (each) => each === name,
  );
}

/**
 * The style of a catalog category. It throws for a name the catalog added
 * without a style here, so the build fails instead of rendering it blank.
 */
export function categoryStyle(name: string): CategoryStyle {
  if (!isCategoryName(name)) {
    throw new Error(
      `The catalog category "${name}" has no style in features/blocks/categories.ts.`,
    );
  }

  return { name, ...STYLES[name] };
}

/** The anchor of a category's section on `/blocks`. */
export function categoryHref(name: string): string {
  return `/blocks#${categoryStyle(name).slug}`;
}
