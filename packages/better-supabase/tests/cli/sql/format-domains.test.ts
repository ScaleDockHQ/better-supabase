import { describe, expect, it } from "vitest";

import {
  formatDomain,
  withFormatDomains,
} from "../../../src/cli/sql/format-domains.ts";
import { constraintChecks } from "../../../src/sql/modules/app-table-checks.ts";

describe("formatDomain", () => {
  it("names the first type plainly and the others with the type", () => {
    expect(formatDomain("rating", "integer")?.name).toBe("bsb.rating");
    expect(formatDomain("rating", "bigint")?.name).toBe("bsb.rating_bigint");
    expect(formatDomain("percent", "numeric")?.name).toBe(
      "bsb.percent_numeric",
    );
  });

  it("renders the pattern and the bounds as a check on value", () => {
    expect(formatDomain("email", "text")?.sql).toMatch(
      /^create domain bsb\.email as text\n {2}constraint email_check check \(value ~\* '/u,
    );

    expect(formatDomain("percent", "integer")?.sql).toContain(
      "check (value >= 0 and value <= 100)",
    );
  });

  it("has no domain for a format without a check or for a type it doesn't fit", () => {
    expect(formatDomain("phone", "text")).toBeUndefined();
    expect(formatDomain("currency", "bigint")).toBeUndefined();
    expect(formatDomain("email", "integer")).toBeUndefined();
  });
});

describe("withFormatDomains", () => {
  const tables = {
    people: {
      columns: {
        email: { type: "text", format: "email" },
        stars: { type: "integer", format: "rating" },
        loose: { type: "integer", format: "rating", min: 0 },
        secret: { type: "text", format: "email", encrypted: true },
        name: { type: "text" },
      },
    },
  } as const;

  it("types the plain format columns and lists their domains once", () => {
    const { tables: typed, domains } = withFormatDomains(tables);
    const columns = typed["people"]?.columns;

    expect(columns?.["email"]?.domain).toBe("bsb.email");
    expect(columns?.["stars"]?.domain).toBe("bsb.rating");
    expect(domains.map((domain) => domain.name)).toEqual([
      "bsb.email",
      "bsb.rating",
    ]);
  });

  it("keeps the inline check of a column with its own bounds or sealed", () => {
    const columns = withFormatDomains(tables).tables["people"]?.columns;

    expect(columns?.["loose"]?.domain).toBeUndefined();
    expect(columns?.["secret"]?.domain).toBeUndefined();
    expect(columns?.["name"]).toEqual({ type: "text" });
  });

  it("leaves the pattern and default bounds to the domain", () => {
    expect(
      constraintChecks(
        { type: "text", format: "email", domain: "bsb.email" },
        "email",
      ),
    ).toEqual([]);

    expect(
      constraintChecks({ type: "text", format: "email" }, "email"),
    ).toHaveLength(1);
  });
});
