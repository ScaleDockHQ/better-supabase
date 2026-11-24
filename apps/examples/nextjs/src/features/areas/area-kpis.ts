import "server-only";
import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";

import type { Kpi } from "@/components/record-list/kpi-band";
import type { AppDb } from "@/lib/block-entity-page";

import { getSession } from "@/features/user/user-queries";
import { bsb } from "@/lib/supabase/server";

import type { AreaId } from "./areas";

/** The rows a KPI counts at most; a larger list shows `100+`. */
const COUNT_LIMIT = 100;

interface Source {
  readonly label: string;
  readonly href: string;
  readonly read: () => PromiseLike<number>;
}

/**
 * The figures of an area hub: the size of the lists its flow walks, each one
 * linking to its page. One page read per figure, capped at `COUNT_LIMIT` rows,
 * so a hub costs as many reads as it shows figures.
 */
async function sourcesOf(
  area: AreaId,
  db: AppDb,
  organizationId: string,
): Promise<readonly Source[]> {
  const t = await getExtracted("areas");
  const options = { organizationId, limit: COUNT_LIMIT } as const;

  switch (area) {
    case "sales": {
      return [
        {
          label: t("Deals"),
          href: "/crm/deals",
          read: async () =>
            (await db.deals.page(options).orThrow()).items.length,
        },
        {
          label: t("Quotes"),
          href: "/crm/quotes",
          read: async () =>
            (await db.quotes.page(options).orThrow()).items.length,
        },
        {
          label: t("Contracts"),
          href: "/crm/contracts",
          read: async () =>
            (await db.contracts.page(options).orThrow()).items.length,
        },
        {
          label: t("Contacts"),
          href: "/crm/contacts",
          read: () => db.contacts.count().orThrow(),
        },
      ];
    }

    case "erp": {
      return [
        {
          label: t("Invoices"),
          href: "/finance/invoices",
          read: async () =>
            (await db.invoices.page(options).orThrow()).items.length,
        },
        {
          label: t("Contracts"),
          href: "/crm/contracts",
          read: async () =>
            (await db.contracts.page(options).orThrow()).items.length,
        },
        {
          label: t("Legal entities"),
          href: "/legal-entities",
          read: async () =>
            (await db.legalEntities.page(options).orThrow()).items.length,
        },
        {
          label: t("Locations"),
          href: "/warehouse",
          read: () => db.locations.count().orThrow(),
        },
      ];
    }

    case "manufacturing": {
      return [
        {
          label: t("Inspections"),
          href: "/inspections",
          read: async () =>
            (await db.inspections.page(options).orThrow()).items.length,
        },
        {
          label: t("Risks"),
          href: "/risks",
          read: async () =>
            (await db.risks.page(options).orThrow()).items.length,
        },
        {
          label: t("Change requests"),
          href: "/production",
          read: () => db.changeRequests.count().orThrow(),
        },
        {
          label: t("Cases"),
          href: "/cases",
          read: async () =>
            (await db.cases.page(options).orThrow()).items.length,
        },
      ];
    }

    case "commerce": {
      return [
        {
          label: t("Customers"),
          href: "/customers",
          read: () => db.customers.count().orThrow(),
        },
        {
          label: t("Warranty claims"),
          href: "/shop/warranty",
          read: async () =>
            (await db.warranty.page(options).orThrow()).items.length,
        },
        {
          label: t("Assets"),
          href: "/dam",
          read: async () =>
            (await db.assets.page(options).orThrow()).items.length,
        },
      ];
    }

    case "service": {
      return [
        {
          label: t("Work orders"),
          href: "/field/dispatch",
          read: async () =>
            (await db.dispatch.page(options).orThrow()).items.length,
        },
        {
          label: t("Facilities"),
          href: "/maintenance",
          read: async () =>
            (await db.facilities.page(options).orThrow()).items.length,
        },
        {
          label: t("Locations"),
          href: "/warehouse",
          read: () => db.locations.count().orThrow(),
        },
      ];
    }

    case "support": {
      return [
        {
          label: t("Cases"),
          href: "/cases",
          read: async () =>
            (await db.cases.page(options).orThrow()).items.length,
        },
        {
          label: t("Incidents"),
          href: "/incidents",
          read: async () =>
            (await db.incidents.page(options).orThrow()).items.length,
        },
        {
          label: t("Channels"),
          href: "/inbox",
          read: async () =>
            (await db.channels.page(options).orThrow()).items.length,
        },
        {
          label: t("Change requests"),
          href: "/incidents",
          read: () => db.changeRequests.count().orThrow(),
        },
      ];
    }

    case "projects": {
      return [
        {
          label: t("Projects"),
          href: "/projects",
          read: () => db.projects.count().orThrow(),
        },
        {
          label: t("Tasks"),
          href: "/work",
          read: () => db.tasks.count().orThrow(),
        },
        {
          label: t("Time entries"),
          href: "/people/time",
          read: async () =>
            (await db.timeEntries.page(options).orThrow()).items.length,
        },
        {
          label: t("Approvals"),
          href: "/approvals",
          read: async () =>
            (await db.approvals.page(options).orThrow()).items.length,
        },
      ];
    }

    case "people": {
      return [
        {
          label: t("Employees"),
          href: "/people",
          read: async () =>
            (await db.employees.page(options).orThrow()).items.length,
        },
        {
          label: t("Courses"),
          href: "/courses",
          read: async () =>
            (await db.courses.page(options).orThrow()).items.length,
        },
        {
          label: t("Time entries"),
          href: "/people/time",
          read: async () =>
            (await db.timeEntries.page(options).orThrow()).items.length,
        },
        {
          label: t("Announcements"),
          href: "/announcements",
          read: async () =>
            (await db.announcements.page(options).orThrow()).items.length,
        },
      ];
    }

    case "content": {
      return [
        {
          label: t("Content entries"),
          href: "/content",
          read: async () =>
            (await db.content.page(options).orThrow()).items.length,
        },
        {
          label: t("Meetings"),
          href: "/meetings",
          read: async () =>
            (await db.meetings.page(options).orThrow()).items.length,
        },
        {
          label: t("Forms"),
          href: "/forms",
          read: async () =>
            (await db.forms.page(options).orThrow()).items.length,
        },
      ];
    }

    case "care": {
      return [
        {
          label: t("Care plans"),
          href: "/care-plans",
          read: async () =>
            (await db.carePlans.page(options).orThrow()).items.length,
        },
        {
          label: t("Observations"),
          href: "/observations",
          read: async () =>
            (await db.observations.page(options).orThrow()).items.length,
        },
        {
          label: t("Client notes"),
          href: "/care",
          read: () => db.clientNotes.count().orThrow(),
        },
      ];
    }

    case "governance": {
      return [
        {
          label: t("Risks"),
          href: "/risks",
          read: async () =>
            (await db.risks.page(options).orThrow()).items.length,
        },
        {
          label: t("Advisories"),
          href: "/advisories",
          read: async () =>
            (await db.advisories.page(options).orThrow()).items.length,
        },
        {
          label: t("Deadlines"),
          href: "/deadlines",
          read: async () =>
            (await db.deadlines.page(options).orThrow()).items.length,
        },
      ];
    }

    case "ai": {
      return [
        {
          label: t("Agents"),
          href: "/assistant/agents",
          read: async () =>
            (await db.agents.page(options).orThrow()).items.length,
        },
        {
          label: t("Prompts"),
          href: "/assistant",
          read: async () =>
            (await db.prompts.page(options).orThrow()).items.length,
        },
        {
          label: t("Schedules"),
          href: "/assistant/agents",
          read: async () =>
            (await db.aiSchedules.page(options).orThrow()).items.length,
        },
        {
          label: t("Approvals"),
          href: "/approvals",
          read: async () =>
            (await db.approvals.page(options).orThrow()).items.length,
        },
      ];
    }

    case "platform": {
      return [
        {
          label: t("Members"),
          href: "/settings/members",
          read: () => db.memberships.count().orThrow(),
        },
        {
          label: t("Domains"),
          href: "/settings/domains",
          read: async () =>
            (await db.domains.page(options).orThrow()).items.length,
        },
        {
          label: t("Access requests"),
          href: "/settings/members",
          read: async () =>
            (await db.accessRequests.page(options).orThrow()).items.length,
        },
      ];
    }

    default: {
      const unreachable: never = area;

      return unreachable;
    }
  }
}

/** The KPI band of an area hub; a figure that fails to read shows a dash. */
export async function areaKpis(area: AreaId): Promise<readonly Kpi[]> {
  const [{ db }, session] = await Promise.all([bsb.context(), getSession()]);
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const sources = await sourcesOf(area, db, tenant);

  const counts = await Promise.allSettled(
    sources.map(async (source) => source.read()),
  );

  return sources.map((source, index) => {
    const count = counts[index];

    const value =
      count?.status === "fulfilled"
        ? count.value >= COUNT_LIMIT
          ? `${COUNT_LIMIT}+`
          : String(count.value)
        : "–";

    return { label: source.label, value, href: source.href };
  });
}
