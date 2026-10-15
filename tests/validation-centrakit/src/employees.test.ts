import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  dbUrl,
  type Extra,
  reachable,
  ROLES,
  type Session,
  USERS,
  withCentraKit,
} from "./stack.ts";

const live = await reachable();

// CentraKit's employees table keeps its own names: first_name is the name,
// kind the employment type and reports_to_employee_id the manager. It has
// no origin or offboarding reason, and the block adopts neither private
// details nor contracts.
const EXTRA: Extra = {
  modules: ["employees"],
  config: {
    employees: {
      mode: "adopt",
      tables: {
        employees: "centrakit.employees",
        privateDetails: null,
        contracts: null,
      },
      columns: {
        employees: {
          tenant: "organization_id",
          name: "first_name",
          email: "work_email",
          team: "department_team_id",
          manager: "reports_to_employee_id",
          employmentType: "kind",
          offboardReason: null,
          originType: null,
          originId: null,
        },
      },
      permissions: {
        read: "people.read",
        write: "people.manage",
        viewSensitive: "people.view-sensitive",
      },
    },
  },
};

async function organization(s: Session): Promise<string> {
  await s.as("service");
  const { rows } = await s.client.query<{ id: string }>(
    "insert into centrakit.organizations (name, slug) values ('Acme', $1) returning id",
    [`acme-${crypto.randomUUID().slice(0, 8)}`],
  );
  const org = rows[0]!.id;
  await s.client.query(
    "insert into centrakit.organization_users (user_id, organization_id, role_id) values ($1, $3, $4), ($2, $3, $5)",
    [USERS.owner, USERS.member, org, ROLES.owner, ROLES.member],
  );
  return org;
}

interface Row {
  readonly id: string;
  readonly first_name: string;
  readonly status: string;
  readonly depth?: number;
}

describe.skipIf(!live)("employees on CentraKit", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("adopts centrakit.employees and keeps its org chart", async () => {
    await withCentraKit(
      pool,
      async (s) => {
        const org = await organization(s);
        await s.as("owner");
        const ada = await s.value<Row>(
          "better_supabase.create_employee($1::uuid, $2::jsonb)",
          [org, { name: "Ada", userId: USERS.owner, jobTitle: "CEO" }],
        );
        expect(ada).toMatchObject({ first_name: "Ada", status: "active" });
        const bob = await s.value<Row & { kind: string }>(
          "better_supabase.create_employee($1::uuid, $2::jsonb)",
          [
            org,
            { name: "Bob", managerId: ada.id, employmentType: "contractor" },
          ],
        );
        expect(bob.kind).toBe("contractor");

        const result = await s.value<{
          accepted: unknown[];
          rejected: { hint: string }[];
        }>("better_supabase.update_employees($1::jsonb)", [
          JSON.stringify([
            { employeeId: ada.id, field: "managerId", value: bob.id },
            { employeeId: bob.id, field: "email", value: "bob@acme.test" },
          ]),
        ]);
        expect(result.accepted).toHaveLength(1);
        expect(result.rejected.map((change) => change.hint)).toEqual([
          "EMPLOYEE_MANAGER_CYCLE",
        ]);

        await s.as("member");
        const chart = await s.value<Row[]>(
          "better_supabase.org_chart($1::uuid, null)",
          [org],
        );
        expect(chart.map((row) => [row.first_name, row.depth])).toEqual([
          ["Ada", 0],
          ["Bob", 1],
        ]);
        expect(
          await s.hint("better_supabase.create_employee($1::uuid, $2::jsonb)", [
            org,
            { name: "Eve" },
          ]),
        ).toBe("EMPLOYEE_FORBIDDEN");

        await s.as("owner");
        const gone = await s.value<Row & { end_date: string }>(
          "better_supabase.offboard_employee($1, '2026-12-31', 'Moved')",
          [bob.id],
        );
        expect(gone).toMatchObject({
          status: "offboarded",
          end_date: "2026-12-31",
        });
      },
      EXTRA,
    );
  });
});
