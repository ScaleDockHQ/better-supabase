import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import {
  emitNavigation,
  listedSubjects,
} from "../../../src/cli/gen/navigation.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

function config(subjects: SubjectsConfig) {
  return resolveConfig({ subjects, blocks: { tenant: {} } }, "/project");
}

describe("navigation and commands", () => {
  it("lists the subjects with a top-level list route", () => {
    const listed = listedSubjects(
      config({
        customer: {
          table: "customers",
          url: "/customers/{id}",
          permissions: { read: "customers:read" },
        },
        company: { table: "companies", url: "/crm/companies/{id}" },
        address: { table: "addresses", url: "/addresses/{id}" },
        box: { table: "boxes", url: "/boxes/{id}" },
        work_day: { table: "work_days", url: "/days/{id}" },
        task: { table: "tasks", url: "/projects/{project_id}/tasks/{id}" },
        root: { table: "roots", url: "/{id}" },
        note: { table: "notes" },
        deal: { table: "deals", url: "/crm/deals" },
      }),
    );

    expect(listed).toEqual([
      {
        type: "address",
        label: "Addresses",
        href: "/addresses",
        record: "/addresses/{id}",
        permission: undefined,
      },
      {
        type: "box",
        label: "Boxes",
        href: "/boxes",
        record: "/boxes/{id}",
        permission: undefined,
      },
      {
        type: "company",
        label: "Companies",
        href: "/crm/companies",
        record: "/crm/companies/{id}",
        permission: undefined,
      },
      {
        type: "customer",
        label: "Customers",
        href: "/customers",
        record: "/customers/{id}",
        permission: "customers:read",
      },
      {
        type: "deal",
        label: "Deals",
        href: "/crm/deals",
        record: "/crm/deals",
        permission: undefined,
      },
      {
        type: "work_day",
        label: "Work days",
        href: "/days",
        record: "/days/{id}",
        permission: undefined,
      },
    ]);
  });

  it("writes both files next to the typed client", () => {
    const files = emitNavigation(
      config({
        customer: {
          table: "customers",
          url: "/customers/{id}",
          permissions: { read: "customers:read" },
        },
        work_day: { table: "work_days", url: "/days/{id}" },
        workday: { table: "workdays", url: "/days/{key}", id: "key" },
        shift: { table: "shifts", url: "/days/{day_id}" },
      }),
    );

    expect(files.map((file) => file.path)).toEqual([
      "src/lib/supabase/navigation.generated.ts",
      "src/lib/supabase/commands.generated.ts",
    ]);

    expect(files[0]?.contents).toMatchSnapshot("navigation");
    expect(files[1]?.contents).toMatchSnapshot("commands");
  });

  it("writes nothing without a list route", () => {
    expect(emitNavigation(config({ note: { table: "notes" } }))).toEqual([]);
  });
});
