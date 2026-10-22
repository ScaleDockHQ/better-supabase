import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const BASE = ["subjects", "versions", "signatures", "reminders", "contracts"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "contracts")
    .map((file) => file.contents)
    .join("\n");

const options = (value: Record<string, unknown>): Layout => ({
  modules: { contracts: { options: value } },
});

describe("contracts module", () => {
  it("reminds the owner options.reminderDays before the notice deadline", () => {
    expect(sqlOf()).toContain('"offset_minutes" = 20160');
    expect(sqlOf(options({ reminderDays: 3 }))).toContain(
      '"offset_minutes" = 4320',
    );

    for (const reminderDays of [-1, 1.5, 366]) {
      expect(() => sqlOf(options({ reminderDays }))).toThrow(
        /reminderDays must be a whole number from 0 to 365/,
      );
    }
  });

  it("references the signature request only when signatures owns its table", () => {
    expect(sqlOf()).toMatch(/signature_request_id" uuid references/);

    const adopted = sqlOf({
      modules: {
        signatures: {
          mode: "adopt",
          tables: { requests: "app.signing_requests" },
        },
      },
    });

    expect(adopted).not.toMatch(/signature_request_id" uuid references/);
  });

  it("checks counterparties against config.subjects and follows their merges", () => {
    const sql = sqlOf({ subjects: { customer: { table: "customers" } } });

    expect(sql).toContain(
      `when 'customer' then exists (select 1 from "public"."customers" s where s."id"::text = v_row."counterparty_id"`,
    );
    expect(sql).toContain(
      "case subject_table when 'public.customers' then array['customer']",
    );
  });

  it("refuses to build on a dependency in custom mode", () => {
    for (const needed of ["signatures", "reminders"]) {
      expect(() =>
        sqlOf({ modules: { [needed]: { mode: "custom" } } }),
      ).toThrow(`blocks.contracts needs the ${needed} tables`);
    }
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { contracts: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    const [contract] = customContracts(["contracts"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_contract",
        "list_contracts",
        "run_contract_renewals",
      ]),
    );
  });
});
