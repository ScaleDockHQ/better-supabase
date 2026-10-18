import {
  ActivityIcon,
  BotIcon,
  BriefcaseIcon,
  CalendarDaysIcon,
  CreditCardIcon,
  ShieldCheckIcon,
  FileTextIcon,
  HandshakeIcon,
  type LucideIcon,
  MessagesSquareIcon,
  ServerCogIcon,
} from "lucide-react";

/** The catalog categories, in the order `catalog.json` lists them. */
export const CATEGORY_NAMES = [
  "Foundation",
  "Collaboration",
  "CRM & sales",
  "Work",
  "Billing & commerce",
  "Scheduling",
  "AI",
  "Content",
  "Operations",
  "Platform",
] as const;

export type CategoryName = (typeof CATEGORY_NAMES)[number];

/**
 * How a category looks wherever it appears. The hue marks categorical
 * identity only; every class is a literal so Tailwind finds it, and each
 * light class has its `dark:` pair.
 */
export interface CategoryStyle {
  readonly name: CategoryName;
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
  Foundation: {
    slug: "foundation",
    icon: ShieldCheckIcon,
    summary:
      "Tenants, organizations, profiles, access, sessions, SSO and the modules the rest build on.",
    text: "text-sky-700 dark:text-sky-300",
    tint: "bg-sky-50 dark:bg-sky-950/40",
    solid: "bg-sky-500 dark:bg-sky-400",
    soft: "bg-sky-500/15 dark:bg-sky-400/20",
    ring: "border-sky-200 dark:border-sky-900",
  },
  Operations: {
    slug: "operations",
    icon: ActivityIcon,
    summary:
      "Audit, feature flags, workflows, onboarding, waitlists, announcements and metrics.",
    text: "text-amber-700 dark:text-amber-300",
    tint: "bg-amber-50 dark:bg-amber-950/40",
    solid: "bg-amber-500 dark:bg-amber-400",
    soft: "bg-amber-500/15 dark:bg-amber-400/20",
    ring: "border-amber-200 dark:border-amber-900",
  },
  Platform: {
    slug: "platform",
    icon: ServerCogIcon,
    summary:
      "Jobs, outbox, webhooks, API keys, rate limits, streams, signing keys and RLS checks.",
    text: "text-indigo-700 dark:text-indigo-300",
    tint: "bg-indigo-50 dark:bg-indigo-950/40",
    solid: "bg-indigo-500 dark:bg-indigo-400",
    soft: "bg-indigo-500/15 dark:bg-indigo-400/20",
    ring: "border-indigo-200 dark:border-indigo-900",
  },
  "Billing & commerce": {
    slug: "billing-commerce",
    icon: CreditCardIcon,
    summary:
      "Entitlements, usage, billing, catalog, inventory, orders, promotions and invoices.",
    text: "text-emerald-700 dark:text-emerald-300",
    tint: "bg-emerald-50 dark:bg-emerald-950/40",
    solid: "bg-emerald-500 dark:bg-emerald-400",
    soft: "bg-emerald-500/15 dark:bg-emerald-400/20",
    ring: "border-emerald-200 dark:border-emerald-900",
  },
  AI: {
    slug: "ai",
    icon: BotIcon,
    summary:
      "Vector search, chat, files, knowledge, memory, agents, connectors and providers.",
    text: "text-violet-700 dark:text-violet-300",
    tint: "bg-violet-50 dark:bg-violet-950/40",
    solid: "bg-violet-500 dark:bg-violet-400",
    soft: "bg-violet-500/15 dark:bg-violet-400/20",
    ring: "border-violet-200 dark:border-violet-900",
  },
  Collaboration: {
    slug: "collaboration",
    icon: MessagesSquareIcon,
    summary:
      "Notifications, comments, attachments, inbox, push, share links and reactions.",
    text: "text-pink-700 dark:text-pink-300",
    tint: "bg-pink-50 dark:bg-pink-950/40",
    solid: "bg-pink-500 dark:bg-pink-400",
    soft: "bg-pink-500/15 dark:bg-pink-400/20",
    ring: "border-pink-200 dark:border-pink-900",
  },
  Work: {
    slug: "work",
    icon: BriefcaseIcon,
    summary:
      "Tags, custom fields, state machines, pipelines, approvals, saved views and work items.",
    text: "text-orange-700 dark:text-orange-300",
    tint: "bg-orange-50 dark:bg-orange-950/40",
    solid: "bg-orange-500 dark:bg-orange-400",
    soft: "bg-orange-500/15 dark:bg-orange-400/20",
    ring: "border-orange-200 dark:border-orange-900",
  },
  Scheduling: {
    slug: "scheduling",
    icon: CalendarDaysIcon,
    summary: "Reminders, calendars, bookings and time tracking.",
    text: "text-cyan-700 dark:text-cyan-300",
    tint: "bg-cyan-50 dark:bg-cyan-950/40",
    solid: "bg-cyan-500 dark:bg-cyan-400",
    soft: "bg-cyan-500/15 dark:bg-cyan-400/20",
    ring: "border-cyan-200 dark:border-cyan-900",
  },
  Content: {
    slug: "content",
    icon: FileTextIcon,
    summary:
      "Imports, versions, trash, documents, drive, forms, signatures and templates.",
    text: "text-fuchsia-700 dark:text-fuchsia-300",
    tint: "bg-fuchsia-50 dark:bg-fuchsia-950/40",
    solid: "bg-fuchsia-500 dark:bg-fuchsia-400",
    soft: "bg-fuchsia-500/15 dark:bg-fuchsia-400/20",
    ring: "border-fuchsia-200 dark:border-fuchsia-900",
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
} satisfies Record<CategoryName, Omit<CategoryStyle, "name">>;

function isCategoryName(name: string): name is CategoryName {
  return CATEGORY_NAMES.some((each) => each === name);
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
