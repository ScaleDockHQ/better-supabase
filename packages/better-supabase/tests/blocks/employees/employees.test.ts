import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createEmployees,
  employeesSubjects,
} from "../../../src/blocks/employees/index.ts";
import { money } from "../../../src/commerce/money.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const EMPLOYEE = {
  id: "e1",
  tenant_id: "o",
  user_id: "u1",
  name: "Mia",
  email: "mia@acme.test",
  job_title: "Designer",
  team_id: "t1",
  manager_id: "e0",
  employment_type: "employee",
  status: "active",
  start_date: "2024-01-01",
  end_date: null,
  offboard_reason: null,
  origin_type: "application",
  origin_id: "a1",
  created_by: "u0",
  created_at: "2026-10-15T09:00:00Z",
  updated_at: "2026-10-15T09:00:00Z",
  shoe_size: "42",
};

const date = (value: string): Temporal.PlainDate =>
  Temporal.PlainDate.from(value);

describe("employees block", () => {
  it("creates employees and parses their extra fields", async () => {
    const t = transport({
      create_employee: () => EMPLOYEE,
      employee_from_application: () => ({ ...EMPLOYEE, status: "preboarding" }),
    });

    const employees = createEmployees({
      transport: t,
      fields: v.object({ shoe_size: v.pipe(v.string(), v.transform(Number)) }),
    });

    const mia = await employees
      .create("o", {
        name: "Mia",
        startDate: date("2024-01-01"),
        fields: { shoe_size: "42" as unknown as number },
      })
      .orThrow();

    expect(mia).toMatchObject({
      organizationId: "o",
      userId: "u1",
      jobTitle: "Designer",
      teamId: "t1",
      managerId: "e0",
      status: "active",
      origin: { type: "application", id: "a1" },
      fields: { shoe_size: 42 },
    });
    expect(mia.startDate?.toString()).toBe("2024-01-01");
    expect(mia.endDate).toBeUndefined();
    expect(mia.createdAt?.toString()).toBe("2026-10-15T09:00:00Z");

    const hired = await employees
      .fromApplication("a1", { jobTitle: "Lead" })
      .orThrow();

    expect(hired.status).toBe("preboarding");
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "create_employee",
        {
          tenant: "o",
          attrs: { name: "Mia", startDate: "2024-01-01", shoe_size: 42 },
        },
      ],
      [
        "employee_from_application",
        { application: "a1", attrs: { jobTitle: "Lead" } },
      ],
    ]);

    const bad = await employees.create("o", {
      name: "Bo",
      fields: { shoe_size: 42 },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(t.calls).toHaveLength(2);
  });

  it("returns a validation error for a row the schema refuses", async () => {
    const employees = createEmployees({
      transport: transport({
        create_employee: () => ({ ...EMPLOYEE, shoe_size: 42 }),
      }),
      fields: v.object({ shoe_size: v.string() }),
    });

    expect(await employees.create("o", { name: "Mia" })).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
  });

  it("sends batched changes and checks extra fields first", async () => {
    const t = transport({
      update_employees: () => ({
        accepted: [{ employeeId: "e1", field: "endDate" }],
        rejected: [
          {
            employeeId: "e2",
            field: "managerId",
            hint: "EMPLOYEE_MANAGER_CYCLE",
            reason: "cycle",
          },
          { employeeId: "e3", field: "name", hint: null, reason: "boom" },
        ],
      }),
    });

    const employees = createEmployees({
      transport: t,
      fields: v.object({ shoe_size: v.number() }),
    });

    const result = await employees
      .update([
        { employeeId: "e1", field: "endDate", value: date("2026-12-31") },
        { employeeId: "e2", field: "managerId", value: "e3" },
        { employeeId: "e3", field: "shoe_size", value: 43 },
      ])
      .orThrow();

    expect(result).toEqual({
      accepted: [{ employeeId: "e1", field: "endDate" }],
      rejected: [
        {
          employeeId: "e2",
          field: "managerId",
          hint: "EMPLOYEE_MANAGER_CYCLE",
          reason: "cycle",
        },
        { employeeId: "e3", field: "name", reason: "boom" },
      ],
    });
    expect(t.calls[0]?.[1]).toEqual({
      changes: [
        { employeeId: "e1", field: "endDate", value: "2026-12-31" },
        { employeeId: "e2", field: "managerId", value: "e3" },
        { employeeId: "e3", field: "shoe_size", value: 43 },
      ],
    });

    const bad = await employees.update([
      { employeeId: "e3", field: "shoe_size", value: "big" },
    ]);

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(t.calls).toHaveLength(1);
  });

  it("offboards and reads the org chart and reports", async () => {
    const t = transport({
      offboard_employee: () => ({
        ...EMPLOYEE,
        status: "offboarded",
        end_date: "2026-12-31",
        offboard_reason: "Moved",
      }),
      org_chart: () => [
        { ...EMPLOYEE, depth: 0, direct_reports: 2 },
        { ...EMPLOYEE, id: "e2", depth: 1 },
      ],
      reports_of: () => [
        { ...EMPLOYEE, id: "e2", depth: "1", direct_reports: "0" },
      ],
    });

    const employees = createEmployees({ transport: t });

    const gone = await employees
      .offboard("e1", { endDate: date("2026-12-31"), reason: "Moved" })
      .orThrow();

    expect(gone).toMatchObject({
      status: "offboarded",
      offboardReason: "Moved",
    });
    await employees.offboard("e1").orThrow();
    const chart = await employees.orgChart("o").orThrow();
    expect(
      chart.map((entry) => [entry.id, entry.depth, entry.directReports]),
    ).toEqual([
      ["e1", 0, 2],
      ["e2", 1, 0],
    ]);
    expect(chart[0]?.fields).toEqual({ shoe_size: "42" });
    await employees.orgChart("o", "e1").orThrow();

    const reports = await employees
      .reportsOf("e1", { indirect: true })
      .orThrow();

    expect(reports[0]).toMatchObject({ id: "e2", depth: 1, directReports: 0 });
    await employees.reportsOf("e1").orThrow();
    expect(t.calls.map(([, args]) => args)).toEqual([
      { employee: "e1", end_date: "2026-12-31", reason: "Moved" },
      { employee: "e1", end_date: null, reason: null },
      { tenant: "o", root: null },
      { tenant: "o", root: "e1" },
      { manager: "e1", indirect: true },
      { manager: "e1", indirect: false },
    ]);
  });

  it("stops the chart at the first row the fields schema refuses", async () => {
    const employees = createEmployees({
      transport: transport({ org_chart: () => [{ ...EMPLOYEE, depth: 0 }] }),
      fields: v.object({ shoe_size: v.number() }),
    });

    expect(await employees.orgChart("o")).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
  });

  it("reads and saves private details and contracts", async () => {
    const t = transport({
      employee_private_details: (args) =>
        args["employee"] === "none"
          ? null
          : {
              employee_id: "e1",
              national_id: "123",
              iban: "NL91ABNA0417164300",
              birth_date: "1990-04-01",
              personal_email: null,
              phone: "+31",
              address: { city: "Utrecht" },
              emergency_contacts: [{ name: "Tom", relation: "partner" }],
              offboarded_at: "2026-10-15T09:00:00Z",
              anonymized_at: null,
            },
      save_employee_private_details: () => ({
        employee_id: "e1",
        address: null,
        emergency_contacts: "oops",
      }),
      employee_contracts: () => [
        {
          id: "c2",
          employee_id: "e1",
          starts_on: "2025-07-01",
          ends_on: null,
          hours_per_week: "40.00",
          salary: "9007199254740993",
          currency: "EUR",
          salary_period: "year",
          note: null,
        },
        {
          id: "c1",
          employee_id: "e1",
          starts_on: "2024-01-01",
          ends_on: "2025-06-30",
          hours_per_week: null,
          salary: null,
          currency: null,
          salary_period: null,
          note: "Part time",
        },
      ],
      add_employee_contract: () => ({
        id: "c3",
        employee_id: "e1",
        starts_on: "2026-01-01",
      }),
    });

    const employees = createEmployees({ transport: t });
    expect(await employees.privateDetails("e1").orThrow()).toMatchObject({
      nationalId: "123",
      address: { city: "Utrecht" },
      emergencyContacts: [{ name: "Tom", relation: "partner" }],
    });
    expect(await employees.privateDetails("none").orThrow()).toBeUndefined();

    const saved = await employees
      .savePrivateDetails("e1", {
        birthDate: date("1990-04-01"),
        emergencyContacts: [{ name: "Tom" }],
        address: null,
      })
      .orThrow();

    expect(saved).toEqual({ employeeId: "e1", emergencyContacts: [] });
    await employees.savePrivateDetails("e1", { phone: null }).orThrow();

    const contracts = await employees.contracts("e1").orThrow();
    expect(contracts[0]).toMatchObject({
      hoursPerWeek: 40,
      salary: money(9_007_199_254_740_993n, "EUR"),
      salaryPeriod: "year",
    });
    expect(contracts[1]).toMatchObject({ note: "Part time" });
    expect(contracts[1]?.salary).toBeUndefined();
    expect(contracts[1]?.endsOn?.toString()).toBe("2025-06-30");
    await employees
      .addContract("e1", {
        startsOn: date("2026-01-01"),
        salary: money(100n, "EUR"),
      })
      .orThrow();
    expect(t.calls.slice(2).map(([, args]) => args)).toEqual([
      {
        employee: "e1",
        attrs: {
          birthDate: "1990-04-01",
          emergencyContacts: [{ name: "Tom" }],
          address: null,
        },
      },
      { employee: "e1", attrs: { phone: null } },
      { employee: "e1" },
      {
        employee: "e1",
        attrs: { startsOn: "2026-01-01", salary: "100", currency: "EUR" },
      },
    ]);
  });

  it("fails a contract row without a start date", async () => {
    const employees = createEmployees({
      transport: transport({
        employee_contracts: () => [{ id: "c1", employee_id: "e1" }],
      }),
    });

    expect((await employees.contracts("e1")).ok).toBe(false);
  });

  it("registers employees as a subject", () => {
    expect(employeesSubjects()).toEqual({
      employee: {
        table: "better_supabase.employees",
        idType: "uuid",
        tenant: "tenant_id",
        title: "name",
        permissions: { read: "employees.read", write: "employees.write" },
        search: { title: "name", body: ["email", "job_title"] },
      },
    });
    expect(
      employeesSubjects({ schema: "hr", url: "/people/{id}" }).employee,
    ).toMatchObject({ table: "hr.employees", url: "/people/{id}" });
  });
});
