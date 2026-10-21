import { describe, expect, it } from "vitest";

import {
  accessToken,
  databaseUrlCredential,
} from "../../../src/cli/core/credentials.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

const bare = resolveConfig({}, "/p");

describe("credentials", () => {
  it("reads the access token from the config, then the environment", () => {
    expect(accessToken(bare, {})).toBeUndefined();
    expect(accessToken(bare, { SUPABASE_ACCESS_TOKEN: "sbp_env" })).toEqual({
      value: "sbp_env",
      from: "$SUPABASE_ACCESS_TOKEN",
    });
    expect(
      accessToken(resolveConfig({ source: { accessToken: "sbp_cfg" } }, "/p"), {
        SUPABASE_ACCESS_TOKEN: "sbp_env",
      }),
    ).toEqual({ value: "sbp_cfg", from: "source.accessToken" });
  });

  it("reads the connection string from stdin, the config, then each variable", () => {
    const env = {
      DATABASE_URL: "postgres://database",
      SUPABASE_DB_URL: "postgres://supabase",
    };

    expect(databaseUrlCredential(bare, {})).toBeUndefined();
    expect(
      databaseUrlCredential(bare, { SUPABASE_DB_URL: env.SUPABASE_DB_URL }),
    ).toEqual({ value: "postgres://supabase", from: "$SUPABASE_DB_URL" });
    expect(databaseUrlCredential(bare, env)?.from).toBe("$DATABASE_URL");
    expect(
      databaseUrlCredential(
        resolveConfig({ source: { dbUrl: "postgres://config" } }, "/p"),
        env,
      )?.from,
    ).toBe("source.dbUrl");
    expect(databaseUrlCredential(bare, env, "postgres://stdin")).toEqual({
      value: "postgres://stdin",
      from: "--db-url-stdin",
    });
  });
});
