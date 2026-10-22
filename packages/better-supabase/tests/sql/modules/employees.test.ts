import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderModules } from "../../../src/sql/render.ts";

const body = (
  modules: readonly string[],
  layout: Parameters<typeof renderModules>[1] = {},
): string =>
  renderModules([...modules], layout)
    .filter((file) => file.module === "employees")
    .map((file) => file.contents)
    .join("\n");

describe("employees module", () => {
  it("guards the manager chain and keeps private details behind view_sensitive", () => {
    const sql = body(["employees"]);
    expect(sql).toContain("EMPLOYEE_MANAGER_CYCLE");
    expect(sql).toContain(
      'create trigger bsb_employee_manager_guard before insert or update of "manager_id"',
    );
    expect(sql).toContain("create trigger bsb_employee_user_mirror");
    expect(sql).toContain("'employees.view_sensitive'");
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

  it("adopts an employees table without the optional columns and tables", () => {
    const layout = {
      modules: {
        employees: {
          mode: "adopt" as const,
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
      },
    };

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
      } as never)
      .map((fn) => fn.name);

    expect(names).toContain("employee_from_application");
    expect(names).toContain("save_employee_private_details");
    expect(names).toContain("add_employee_contract");
  });

  it("renders nothing in custom mode", () => {
    expect(
      body(["employees"], { modules: { employees: { mode: "custom" } } }),
    ).not.toContain("create_employee");
  });
});
