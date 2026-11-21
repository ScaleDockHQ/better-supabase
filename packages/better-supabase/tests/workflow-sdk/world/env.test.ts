import { describe, expect, it } from "vitest";

import {
  connectionStringFrom,
  worldOptionsFromEnv,
} from "../../../src/workflow-sdk/world/env.ts";

const url = (name: string) => `postgresql://u@${name}/db`;

describe("connectionStringFrom", () => {
  it("reads the variables in order, and ignores empty ones", () => {
    const from = (env: Record<string, string>) =>
      connectionStringFrom((name) =>
        env[name] === "" ? undefined : env[name],
      );

    expect(
      from({
        POSTGRES_URL: url("pooled"),
        POSTGRES_URL_NON_POOLING: url("direct"),
      }),
    ).toBe(url("pooled"));
    expect(from({ POSTGRES_URL_NON_POOLING: url("direct") })).toBe(
      url("direct"),
    );
    expect(
      from({
        POSTGRES_URL: url("pooled"),
        DATABASE_URL: url("database"),
        SUPABASE_DB_URL: url("supabase"),
        WORKFLOW_POSTGRES_URL: "",
      }),
    ).toBe(url("supabase"));
    expect(
      from({
        WORKFLOW_POSTGRES_URL: url("own"),
        DATABASE_URL: url("database"),
      }),
    ).toBe(url("own"));
    expect(from({})).toBeUndefined();
  });
});

describe("worldOptionsFromEnv on Vercel", () => {
  it("takes the integration's connection string", () => {
    expect(
      worldOptionsFromEnv({ POSTGRES_URL_NON_POOLING: url("direct") }),
    ).toEqual({ connectionString: url("direct") });
  });

  it("adds the protection bypass header for a flow route on this deployment", () => {
    expect(
      worldOptionsFromEnv({
        VERCEL_URL: "app-abc-team.vercel.app",
        VERCEL_AUTOMATION_BYPASS_SECRET: "s3cret",
        WORKFLOW_FLOW_URL:
          "https://app-abc-team.vercel.app/.well-known/workflow/v1/flow",
      }).deliveryHeaders,
    ).toEqual({ "x-vercel-protection-bypass": "s3cret" });
  });

  it("keeps the secret off another host and lets explicit headers win", () => {
    expect(
      worldOptionsFromEnv({
        VERCEL_URL: "app-abc-team.vercel.app",
        VERCEL_AUTOMATION_BYPASS_SECRET: "s3cret",
        WORKFLOW_FLOW_URL: "https://elsewhere.example.com/flow",
      }).deliveryHeaders,
    ).toBeUndefined();

    expect(
      worldOptionsFromEnv({
        VERCEL_URL: "app-abc-team.vercel.app",
        VERCEL_AUTOMATION_BYPASS_SECRET: "s3cret",
        WORKFLOW_FLOW_URL: "https://app-abc-team.vercel.app/flow",
        WORKFLOW_DELIVERY_HEADERS: '{"x-vercel-protection-bypass":"own"}',
      }).deliveryHeaders,
    ).toEqual({ "x-vercel-protection-bypass": "own" });
  });
});
