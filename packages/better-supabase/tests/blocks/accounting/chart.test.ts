import { describe, expect, it } from "vitest";

import type {
  AccountingChartFormat,
  ChartAccount,
} from "../../../src/blocks/accounting/index.ts";

import {
  chartFormatOf,
  importChart,
} from "../../../src/blocks/accounting/index.ts";
import { err, ok } from "../../../src/core/result.ts";

/** A reference format: `code;name;type;parent;roles` lines, like an RGS export. */
const csv: AccountingChartFormat = {
  apiVersion: 1,
  key: "csv-reference",
  parse(body) {
    return body
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map((line): ChartAccount => {
        const [code = "", name = "", type = "", parent = "", roles = ""] =
          line.split(";");

        return {
          code,
          name,
          // SAFETY: the fixtures only use valid account types.
          type: type as ChartAccount["type"],
          ...(parent ? { parentCode: parent } : {}),
          // SAFETY: the fixtures only use valid roles.
          roles: (roles ? roles.split(",") : []) as NonNullable<
            ChartAccount["roles"]
          >,
        };
      });
  },
};

function fakeAccounting(failOn?: string) {
  const saved: { code: string; parentId?: string }[] = [];
  const roles: Record<string, string> = {};

  return {
    saved,
    roles,
    accounting: {
      saveAccount(_org: string, input: { code: string; parentId?: string }) {
        if (input.code === failOn) {
          return Promise.resolve(
            err({ kind: "unknown", message: "boom", status: 500 }),
          );
        }

        saved.push(input);

        return Promise.resolve(ok({ id: `id-${input.code}`, ...input }));
      },
      setAccountRole(_org: string, role: string, accountId: string) {
        if (failOn === "role") {
          return Promise.resolve(
            err({ kind: "unknown", message: "boom", status: 500 }),
          );
        }

        roles[role] = accountId;

        return Promise.resolve(ok({ ...roles }));
      },
      // SAFETY: the importer only calls these two methods.
    } as never,
  };
}

describe("importChart", () => {
  it("saves parents first and maps roles", async () => {
    const { accounting, saved, roles } = fakeAccounting();

    const result = await importChart(
      accounting,
      "o",
      csv,
      "1100;Debiteuren;asset_receivable;1000;receivable\n1000;Vorderingen;asset_current;;\n",
    );

    expect(result.ok).toBe(true);
    expect(saved.map((account) => account.code)).toEqual(["1000", "1100"]);
    expect(saved[1]?.parentId).toBe("id-1000");
    expect(roles).toEqual({ receivable: "id-1100" });
  });

  it("returns the format key and the mapped roles", async () => {
    const { accounting } = fakeAccounting();
    const result = await importChart(accounting, "o", csv, "1000;A;asset;;");

    expect(result.ok && result.data.format).toBe("csv-reference");
    expect(result.ok && result.data.roles).toEqual({});
  });

  it.each([
    ["a code twice", "1;A;asset;;\n1;B;asset;;"],
    ["a missing parent", "2;A;asset;9;"],
    ["a parent cycle", "1;A;asset;2;\n2;B;asset;1;"],
    ["a role on two accounts", "1;A;asset;;bank\n2;B;asset;;bank"],
  ])("refuses %s and saves nothing", async (_name, body) => {
    const { accounting, saved } = fakeAccounting();
    const result = await importChart(accounting, "o", csv, body);

    expect(result.ok ? undefined : result.error.hint).toBe(
      "ACCOUNTING_CHART_INVALID",
    );
    expect(saved).toHaveLength(0);
  });

  it("returns a save failure", async () => {
    const { accounting } = fakeAccounting("1");
    const result = await importChart(accounting, "o", csv, "1;A;asset;;");

    expect(result.ok).toBe(false);
  });

  it("returns a role failure", async () => {
    const { accounting } = fakeAccounting("role");
    const result = await importChart(accounting, "o", csv, "1;A;asset;;bank");

    expect(result.ok).toBe(false);
  });

  it("returns a throwing format as an error result", async () => {
    const { accounting } = fakeAccounting();

    const result = await importChart(
      accounting,
      "o",
      {
        apiVersion: 1,
        key: "bad",
        parse() {
          throw new Error("unreadable");
        },
      },
      "",
    );

    expect(result.ok).toBe(false);
  });

  it("rejects another apiVersion", () => {
    expect(() =>
      // SAFETY: simulates a format built for a newer API.
      chartFormatOf({ apiVersion: 2, key: "x", parse: () => [] } as never),
    ).toThrow(TypeError);
  });
});
