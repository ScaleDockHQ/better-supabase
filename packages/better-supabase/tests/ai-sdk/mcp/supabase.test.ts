import { describe, expect, it } from "vitest";

import {
  SUPABASE_MCP_URL,
  supabaseMcp,
} from "../../../src/ai-sdk/mcp/index.ts";

describe("supabaseMcp", () => {
  it("scopes the hosted server read-only by default and types its tools", async () => {
    const supabase = await supabaseMcp({
      projectRef: "abcdefghijklmnopqrst",
      features: ["database", "docs"],
    });

    const url = new URL(supabase.url);
    expect(url.origin + url.pathname).toBe(SUPABASE_MCP_URL);
    expect(Object.fromEntries(url.searchParams)).toEqual({
      project_ref: "abcdefghijklmnopqrst",
      read_only: "true",
      features: "database,docs",
    });
    expect(Object.keys(supabase.schemas).toSorted()).toEqual([
      "execute_sql",
      "list_extensions",
      "list_migrations",
      "list_tables",
      "search_docs",
    ]);
    const listTables = supabase.schemas["list_tables"];
    expect(listTables?.outputSchema).toBeDefined();
  });

  it("keeps the write tools when readOnly is false, on a local stack", async () => {
    const supabase = await supabaseMcp({
      readOnly: false,
      features: ["database"],
      url: "http://localhost:54321/mcp",
    });

    expect(supabase.url).toBe("http://localhost:54321/mcp?features=database");
    expect(Object.keys(supabase.schemas)).toContain("apply_migration");
  });
});
