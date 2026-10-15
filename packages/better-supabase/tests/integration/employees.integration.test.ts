import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createEmployees,
  employeesSubjects,
} from "../../src/blocks/employees/index.ts";
import { createHiring } from "../../src/blocks/hiring/index.ts";
import {
  createParties,
  partiesSubjects,
} from "../../src/blocks/parties/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "relations",
  "parties",
  "pipelines",
  "hiring",
  "employees",
];
const layout: ModuleLayout = {
  subjects: {
    ...partiesSubjects(),
    ...employeesSubjects(),
    application: {
      table: "better_supabase.applications",
      idType: "uuid",
      tenant: "tenant_id",
    },
  },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const date = (value: string): Temporal.PlainDate =>
  Temporal.PlainDate.from(value);

describe.skipIf(!live)("employees", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keeps an org chart, private details, contracts and offboarding", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const lead = await s.user("lead");
      const colleague = await s.user("colleague");
      const outsider = await s.user("outsider");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, {
        viewer: lead,
        member: colleague,
      });
      const employees = createEmployees({ transport: sqlTransport(s.sql) });

      await s.as(owner);
      const ceo = await employees
        .create(org, {
          name: "Grace",
          userId: owner.id,
          jobTitle: "CEO",
          startDate: date("2020-01-01"),
        })
        .orThrow();
      expect(ceo).toMatchObject({
        status: "active",
        employmentType: "employee",
        userId: owner.id,
      });
      const mia = await employees
        .create(org, { name: "Mia", userId: lead.id, managerId: ceo.id })
        .orThrow();
      const sam = await employees
        .create(org, {
          name: "Sam",
          managerId: mia.id,
          employmentType: "contractor",
          startDate: Temporal.Now.plainDateISO().add({ days: 30 }),
        })
        .orThrow();
      expect(sam.status).toBe("preboarding");
      expect(sam.userId).toBeUndefined();
      expect(
        hint(await employees.create(org, { name: "Ann", userId: outsider.id })),
      ).toBe("EMPLOYEE_USER_NOT_MEMBER");
      expect(
        hint(await employees.create(org, { name: "Bo", userId: owner.id })),
      ).toBe("EMPLOYEE_USER_TAKEN");
      expect(
        hint(await employees.create(org, { name: "Cy", employmentType: "x" })),
      ).toBe("EMPLOYEE_TYPE_INVALID");

      const changes = await employees
        .update([
          { employeeId: ceo.id, field: "managerId", value: sam.id },
          { employeeId: sam.id, field: "jobTitle", value: "Designer" },
          { employeeId: sam.id, field: "status", value: "offboarded" },
          { employeeId: sam.id, field: "nickname", value: "S" },
          { employeeId: mia.id, field: "endDate", value: date("2019-01-01") },
        ])
        .orThrow();
      expect(changes.accepted).toEqual([
        { employeeId: sam.id, field: "jobTitle" },
        { employeeId: mia.id, field: "endDate" },
      ]);
      expect(changes.rejected.map((change) => change.hint)).toEqual([
        "EMPLOYEE_MANAGER_CYCLE",
        "EMPLOYEE_STATUS_INVALID",
        "EMPLOYEE_FIELD_UNKNOWN",
      ]);

      const chart = await employees.orgChart(org).orThrow();
      expect(chart.map((entry) => [entry.name, entry.depth])).toEqual([
        ["Grace", 0],
        ["Mia", 1],
        ["Sam", 2],
      ]);
      expect(chart[0]?.directReports).toBe(1);

      // The lead is a viewer: no employees.read, but they see their own reports.
      await s.as(lead);
      expect(
        (await employees.reportsOf(mia.id).orThrow()).map((r) => r.name),
      ).toEqual(["Sam"]);
      expect(
        (await employees.orgChart(org, mia.id).orThrow()).map((r) => r.name),
      ).toEqual(["Mia", "Sam"]);
      expect(hint(await employees.orgChart(org))).toBe("EMPLOYEE_FORBIDDEN");
      expect(hint(await employees.reportsOf(ceo.id))).toBe(
        "EMPLOYEE_NOT_FOUND",
      );

      await s.as(owner);
      expect(
        (await employees.reportsOf(ceo.id, { indirect: true }).orThrow()).map(
          (r) => [r.name, r.depth],
        ),
      ).toEqual([
        ["Mia", 1],
        ["Sam", 2],
      ]);
      const details = await employees
        .savePrivateDetails(mia.id, {
          iban: "nl91 abna 0417 1643 00",
          birthDate: date("1990-04-01"),
          emergencyContacts: [{ name: "Tom", relation: "partner" }],
        })
        .orThrow();
      expect(details).toMatchObject({
        iban: "NL91ABNA0417164300",
        emergencyContacts: [{ name: "Tom", relation: "partner" }],
      });
      expect(
        hint(await employees.savePrivateDetails(mia.id, { iban: "nope" })),
      ).toBe("EMPLOYEE_PRIVATE_INVALID");
      expect(await employees.privateDetails(sam.id).orThrow()).toBeUndefined();

      const first = await employees
        .addContract(mia.id, {
          startsOn: date("2024-01-01"),
          hoursPerWeek: 32,
          salary: 5_400_000n,
          currency: "eur",
          salaryPeriod: "year",
        })
        .orThrow();
      expect(first).toMatchObject({ salary: 5_400_000n, currency: "EUR" });
      await employees
        .addContract(mia.id, {
          startsOn: date("2025-07-01"),
          hoursPerWeek: 40,
          salary: 9_007_199_254_740_993n,
          currency: "EUR",
        })
        .orThrow();
      expect(
        hint(
          await employees.addContract(mia.id, { startsOn: date("2025-01-01") }),
        ),
      ).toBe("EMPLOYEE_CONTRACT_OVERLAP");
      const contracts = await employees.contracts(mia.id).orThrow();
      expect(contracts.map((c) => c.endsOn?.toString() ?? null)).toEqual([
        null,
        "2025-06-30",
      ]);
      expect(contracts[0]?.salary).toBe(9_007_199_254_740_993n);

      // The employee reads their own details; a colleague sees neither.
      await s.as(lead);
      expect((await employees.privateDetails(mia.id).orThrow())?.iban).toBe(
        "NL91ABNA0417164300",
      );
      expect(await employees.contracts(mia.id).orThrow()).toHaveLength(2);
      await s.as(colleague);
      expect(hint(await employees.privateDetails(mia.id))).toBe(
        "EMPLOYEE_NOT_FOUND",
      );
      await s.asRole(colleague);
      expect(
        await s.rows(
          "select employee_id from better_supabase.employee_private_details",
        ),
      ).toEqual([]);
      expect(
        await s.rows("select id from better_supabase.employee_contracts"),
      ).toEqual([]);
      expect(
        (await s.rows("select id from better_supabase.employees")).length,
      ).toBe(3);
      await s.asRole(lead);
      expect(
        (
          await s.rows(
            "select employee_id from better_supabase.employee_private_details",
          )
        ).length,
      ).toBe(1);
      expect(
        (await s.rows("select id from better_supabase.employees")).length,
      ).toBe(1);

      await s.as(owner);
      const gone = await employees
        .offboard(mia.id, { endDate: date("2026-12-31"), reason: "Moved" })
        .orThrow();
      expect(gone).toMatchObject({
        status: "offboarded",
        offboardReason: "Moved",
      });
      expect(gone.endDate?.toString()).toBe("2026-12-31");
      expect((await employees.offboard(mia.id).orThrow()).endDate).toEqual(
        gone.endDate,
      );
      expect(
        (await employees.reportsOf(ceo.id).orThrow()).map((r) => r.name),
      ).toEqual(["Sam"]);
      expect(
        (await employees.privateDetails(mia.id).orThrow())?.offboardedAt,
      ).toBeDefined();
      const rehired = await employees
        .update([{ employeeId: mia.id, field: "status", value: "active" }])
        .orThrow();
      expect(rehired.accepted).toHaveLength(1);
      const back = await employees.orgChart(org, mia.id).orThrow();
      expect(back[0]).toMatchObject({ status: "active", depth: 0 });
      expect(back[0]?.endDate).toBeUndefined();

      const events = await s.rows<{
        type: string;
        payload: { fields?: string[] };
      }>(
        "select type, payload from better_supabase.outbox_events where organization_id = $1 and type like 'employee.%' order by created_at, id",
        [org],
      );
      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "employee.created",
          "employee.updated",
          "employee.manager_changed",
          "employee.offboarded",
        ]),
      );
      expect(
        events.filter((row) => row.type === "employee.manager_changed"),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });

  it("makes one employee from a hired application", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      await s.install(MODULES, layout);
      const org = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const hiring = createHiring({ transport });
      const employees = createEmployees({ transport });

      await s.as(owner);
      const job = await hiring
        .saveJob(org, {
          title: "Backend engineer",
          employmentType: "employee",
          status: "open",
        })
        .orThrow();
      const ada = await createParties({ transport })
        .savePerson(org, { name: "Ada" })
        .orThrow();
      const application = await hiring.apply(job.id, { id: ada.id }).orThrow();
      expect(hint(await employees.fromApplication(application.id))).toBe(
        "EMPLOYEE_APPLICATION_NOT_HIRED",
      );
      await hiring.hire(application.id).orThrow();

      const hired = await employees
        .fromApplication(application.id, { startDate: date("2026-11-01") })
        .orThrow();
      expect(hired).toMatchObject({
        name: "Ada",
        jobTitle: "Backend engineer",
        employmentType: "employee",
        status: "preboarding",
        origin: { type: "application", id: application.id },
      });
      expect(
        (await employees.fromApplication(application.id).orThrow()).id,
      ).toBe(hired.id);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.relations where kind = 'created_from' and source_type = 'employee' and source_id = $1 and target_type = 'application' and target_id = $2)",
          [hired.id, application.id],
        ),
      ).toBe(1);
      expect(hint(await employees.fromApplication(crypto.randomUUID()))).toBe(
        "EMPLOYEE_ORIGIN_NOT_FOUND",
      );
    } finally {
      await s.close();
    }
  });
});
