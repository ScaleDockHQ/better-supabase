import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

// PostgREST 12 aggregate grammar: `alias:column.fn()` (optionally `::cast`)
// for sum, avg, min, max and count, plus bare `count()`, next to plain
// grouping columns.
const FIELD = "[A-Za-z_][A-Za-z0-9_]*";
const AGG = `(?:${FIELD}:)?(?:${FIELD}\\.(?:sum|avg|min|max|count)\\(\\)|count\\(\\))(?:::${FIELD})?`;
const COLUMN = `(?:${FIELD}:)?${FIELD}`;
const ITEM = new RegExp(`^(?:${AGG}|${COLUMN})$`);

/** Splits a select list on top-level commas. */
function items(select: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let current = "";
  for (const char of select) {
    if (char === "(") depth += 1;
    if (char === ")") depth -= 1;
    if (char === "," && depth === 0) {
      out.push(current);
      current = "";
    } else current += char;
  }
  return [...out, current];
}

describe(`PostgREST aggregate functions (PostgREST ${SPEC_PINS.postgrestAggregates}+)`, () => {
  const betterSupabase = defineSupabase(schema);

  it("compiles aggregate() to the aggregate select grammar with group-by columns", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ status: "active", _count: 2 }],
    }));
    await betterSupabase.connect(client).customers.aggregate({
      groupBy: ["status"],
      _count: true,
      _min: { createdAt: true },
      _max: { createdAt: true },
    });
    const select = last().params.get("select")!;
    for (const item of items(select)) expect(item).toMatch(ITEM);
    expect(items(select)).toContain("status");
    expect(items(select)).toContain("_count:count()");
    expect(items(select)).toContain("_min_createdAt:created_at.min()");
  });

  it("compiles _sum/_avg/_min/_max includes to embedded aggregates", async () => {
    const { client, last } = capturingClient(() => ({ body: [] }));
    await betterSupabase.connect(client).customers.findMany({
      select: ["id"],
      include: {
        _sum: { notes: { id: true } },
        _max: { notes: { createdAt: true } },
      },
    });
    const select = last().params.get("select")!;
    const embedded = items(select).filter((item) => item.includes("("));
    expect(embedded.length).toBe(2);
    for (const item of embedded) {
      const inner = /\(([^]*)\)$/.exec(item.replace(/^[^(]*\(/, "("))![1]!;
      for (const part of items(inner)) expect(part).toMatch(ITEM);
    }
  });

  it("rejects _sum on a non-numeric column before sending a request", async () => {
    const { client, requests } = capturingClient();
    const result = await betterSupabase.connect(client).customers.findMany({
      include: { _sum: { notes: { body: true } } } as never,
    });
    expect(result.ok).toBe(false);
    expect(requests).toHaveLength(0);
  });
});
