import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, resolveModules } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("agents", { modules })!;

describe("agents module", () => {
  it("owns agents, installs, ratings and skills", () => {
    const sql = body();
    for (const table of [
      "agents",
      "agent_installs",
      "agent_ratings",
      "agent_skills",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }
    expect(sql).toContain("'^[a-z0-9]+(-[a-z0-9]+)*$'");
  });

  it("publishes through ai_chat.share and moderates through ai_chat.moderate", () => {
    const sql = body();
    expect(sql).toContain("'ai_chat.share'");
    expect(sql).toContain("'ai_chat.moderate'");
    expect(sql).toContain("AGENT_SLUG_TAKEN");
    expect(sql).toContain("AGENT_FORBIDDEN");
  });

  it("defines the store functions", () => {
    const sql = body();
    for (const name of [
      "save_agent",
      "publish_agent",
      "delete_agent",
      "get_agent",
      "list_agents",
      "install_agent",
      "rate_agent",
      "set_agent_skills",
    ]) {
      expect(sql).toContain(`function "better_supabase"."${name}"(`);
    }
  });

  it("caps instructions at maxInstructions", () => {
    expect(body({ agents: { options: { maxInstructions: 500 } } })).toContain(
      "500",
    );
  });

  it("needs tenant and access", () => {
    const names = resolveModules(["agents"]).map((module) => module.name);
    expect(names).toContain("tenant");
    expect(names).toContain("access");
    expect(names.at(-1)).toBe("agents");
  });
});
