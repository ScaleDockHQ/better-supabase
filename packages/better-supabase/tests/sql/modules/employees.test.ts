import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const body = (
  modules: readonly string[],
  layout: Parameters<typeof renderBlocks>[1] = {},
): string =>
  renderBlocks([...modules], layout)
    .filter((file) => file.module === "employees")
    .map((file) => file.contents)
    .join("\n");

describe("employees module", () => {
  it("needs the private details write key with read_sensitive when set", () => {
    const sql = body(["employees"], {
      modules: {
        employees: { permissions: { privateDetailsWrite: "people.write" } },
      },
    });

    expect(sql).toMatch(
      /save_employee_private_details[\s\S]*'employees\.read_sensitive'[\s\S]*'people\.write'/u,
    );
    expect(body(["employees"])).not.toContain("people.write");
  });

  it("guards the manager chain and keeps private details behind read_sensitive", () => {
    const sql = body(["employees"]);
    expect(sql).toContain("EMPLOYEE_MANAGER_CYCLE");
    expect(sql).toContain(
      'create trigger bsb_employee_manager_guard before insert or update of "manager_id"',
    );
    expect(sql).toContain("create trigger bsb_employee_user_mirror");
    expect(sql).toContain("'employees.read_sensitive'");
    expect(sql).toContain(
      "array['employee', 'contractor', 'intern', 'temporary']::text[]",
    );
    // Without hiring or relations, no application hand-off and no link.
    expect(sql).not.toContain("employee_from_application");
    expect(sql).not.toContain("created_from");
  });

  it("makes employees from hired applications with hiring and relations", () => {
    const sql = body(["relations", "pipelines", "hiring", "employees"], {
      subjects: {
        person: { table: "app.people", idType: "uuid", title: "full_name" },
      },
    });

    expect(sql).toContain("employee_from_application");
    expect(sql).toContain("'created_from'");
    expect(sql).toContain('select s."full_name"::text from "app"."people" s');
  });

  it("takes employment types and extra columns", () => {
    const sql = body(["employees"], {
      modules: {
        employees: {
          options: {
            employmentTypes: ["permanent", "freelance"],
            extraColumns: { shoe_size: "integer" },
          },
        },
      },
    });

    expect(sql).toContain("array['permanent', 'freelance']::text[]");
    expect(sql).toContain('add column if not exists "shoe_size" integer');
    expect(sql).toContain("when 'shoe_size' then");
    expect(() =>
      body(["employees"], {
        modules: {
          employees: { options: { extraColumns: { depth: "integer" } } },
        },
      }),
    ).toThrow(/depth/);
  });

  it("runs over the app's employees table without the optional columns and tables", () => {
    const modules = {
      employees: {
        tables: {
          employees: "hr.staff",
          privateDetails: null,
          contracts: null,
        },
        columns: {
          employees: {
            tenant: "organization_id",
            email: null,
            jobTitle: null,
            team: null,
            employmentType: null,
            startDate: null,
            endDate: null,
            offboardReason: null,
            originType: null,
            originId: null,
            createdBy: null,
            createdAt: null,
            updatedAt: null,
          },
        },
      },
    };

    const layout = { modules, ownTables: ownTablesOf(modules) };

    const sql = body(["outbox", "hiring", "pipelines", "employees"], layout);
    expect(sql).not.toContain('create table if not exists "hr"');
    expect(sql).not.toContain("employee_private_details");
    expect(sql).not.toContain("employee_contracts");
    expect(sql).not.toContain("employee_from_application");
    expect(sql).not.toContain("EMPLOYEE_TYPE_INVALID");
    expect(sql).toContain(
      "coalesce(create_employee.attrs ->> 'status', 'active')",
    );
    expect(sql).toContain("'endDate', current_date");

    const names = SQL_MODULES["employees"]
      ?.contract?.({
        installed: () => false,
        hasTable: () => false,
        has: () => false,
      } as never)
      .map((fn) => fn.name);

    expect(names).toEqual([
      "create_employee",
      "update_employees",
      "delete_employee",
      "offboard_employee",
      "org_chart",
      "reports_of",
    ]);
  });

  it("lists every function in its contract when everything is there", () => {
    const names = SQL_MODULES["employees"]
      ?.contract?.({
        installed: () => true,
        hasTable: () => true,
        has: () => true,
        option: () => undefined,
      } as never)
      .map((fn) => fn.name);

    expect(names).toContain("employee_from_application");
    expect(names).toContain("save_employee_private_details");
    expect(names).toContain("add_employee_contract");
  });

  it("denies contract overlaps and keeps reports on offboarding when asked", () => {
    const sql = body(["employees"], {
      modules: {
        employees: {
          options: {
            contractOverlap: "deny",
            offboarding: { reports: "keep" },
          },
        },
      },
    });

    expect(sql).toContain("&& daterange(");
    expect(sql).toContain(
      'create or replace function "better_supabase"."delete_employee"',
    );
    expect(sql).toContain("EMPLOYEE_IN_USE");
    expect(body(["employees"])).not.toContain("&& daterange(");
    expect(() =>
      body(["employees"], {
        modules: {
          employees: { options: { offboarding: { reports: "drop" } } },
        },
      }),
    ).toThrow(/reports/u);
  });

  it("renders nothing in custom mode", () => {
    expect(
      body(["employees"], { modules: { employees: { mode: "custom" } } }),
    ).not.toContain("create_employee");
  });

  it("keys time entries to employees with time-tracking", () => {
    expect(body(["employees"])).not.toContain(
      "add column if not exists employee_id",
    );
    const sql = body(["approvals", "time-tracking", "employees"]);
    expect(sql).toContain(
      'alter table "better_supabase"."time_entries" add column if not exists employee_id uuid references "better_supabase"."employees" ("id") on delete set null;',
    );
    expect(sql).toContain(
      'create trigger bsb_time_entries_employee before insert or update of "user_id" on "better_supabase"."time_entries"',
    );
    expect(sql).toContain(
      'create trigger bsb_time_entries_employee_sync after insert or update of "user_id" on "better_supabase"."employees"',
    );
    expect(sql).not.toMatch(/^update /m);

    const plan = upgradePlan([
      { module: "approvals", version: 99 },
      { module: "time-tracking", version: 99 },
      { module: "employees", version: 1 },
    ]).find((entry) => entry.module === "employees");

    const upgrade = plan?.steps[0]?.sql ?? "";
    expect(upgrade).toContain(
      'alter table "better_supabase"."time_entries" disable trigger bsb_time_entry_guard;',
    );
    expect(upgrade).toContain(
      'update "better_supabase"."time_entries" t set employee_id',
    );
  });

  it("puts the employee's user on every employee event", () => {
    const sql = body(["outbox", "employees"]);

    const events = [
      ...sql.matchAll(/emit_event\('employee\.[a-z_]+', ([^\n]+)/gu),
    ];

    expect(events.length).toBeGreaterThan(0);

    for (const [, payload] of events) {
      expect(payload).toContain("'userId'");
    }
  });
});
