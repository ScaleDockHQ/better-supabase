import { describe, expect, it, vi } from "vitest";

import {
  loadSupabaseMcp,
  loadSupabaseMcpPlatform,
} from "../../src/core/supabase-mcp.ts";

vi.mock("@supabase/mcp-server-supabase", () => ({}));

vi.mock("@supabase/mcp-server-supabase/platform/api", () => ({}));

describe("loadSupabaseMcp", () => {
  it("explains how to install the package when it is missing", async () => {
    await expect(loadSupabaseMcp()).rejects.toThrow(
      "pnpm add @supabase/mcp-server-supabase",
    );
    await expect(loadSupabaseMcpPlatform()).rejects.toThrow(
      "pnpm add @supabase/mcp-server-supabase",
    );
  });
});
