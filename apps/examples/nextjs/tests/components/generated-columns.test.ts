import { describe, expect, it } from "vitest";

import { generatedBlockColumns } from "@/components/record-list/generated-columns";
import { contractsColumns } from "@/lib/supabase/pages/contracts.columns";
import { blockOverviewParsers } from "@/lib/block-overview-params";
import { parseBlockList } from "@/lib/block-overview-query";

describe("generatedBlockColumns", () => {
  const columns = generatedBlockColumns({
    columns: contractsColumns,
    header: (column) => column.label,
    link: { key: "title", href: "/crm/contracts/{id}" },
    order: ["title", "value", "endsOn", "status"],
    overrides: { status: { size: 150 } },
    extra: [{ key: "value", header: "Value", kind: "number" }],
  });

  it("maps descriptor kinds to cell kinds and links the title", () => {
    expect(columns.map((column) => [column.key, column.kind])).toEqual([
      ["title", "link"],
      ["value", "number"],
      ["endsOn", "muted"],
      ["status", "text"],
    ]);
    expect(columns[0]?.href).toBe("/crm/contracts/{id}");
  });

  it("applies overrides and drops keys outside the order", () => {
    expect(columns.find((column) => column.key === "status")?.size).toBe(150);
  });
});

describe("block overview params", () => {
  it("defaults every key to an empty string", () => {
    expect(Object.keys(blockOverviewParsers)).toEqual(["q", "f", "sort", "after"]);
  });

  it("reads the first value and trims the search", () => {
    expect(parseBlockList({ q: ["  acme ", "x"], f: "active", after: "c1" })).toEqual({
      q: "acme",
      sort: "",
      after: "c1",
      facets: { f: ["active"] },
    });
  });
});
