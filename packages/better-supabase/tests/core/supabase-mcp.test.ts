import { describe, expect, it, vi } from "vitest";

import {
  getSupabaseMcp,
  getSupabaseMcpPlatform,
} from "../../src/core/supabase-mcp.ts";

vi.mock(import("@supabase/mcp-server-supabase"), () => ({}));

vi.mock(import("@supabase/mcp-server-supabase/platform/api"), () => ({}));

describe("loadSupabaseMcp", () => {
  it("explains how to install the package when it is missing", async () => {
    await expect(getSupabaseMcp()).rejects.toThrow(
      "pnpm add @supabase/mcp-server-supabase",
    );
    await expect(getSupabaseMcpPlatform()).rejects.toThrow(
      "pnpm add @supabase/mcp-server-supabase",
    );
  });
});
