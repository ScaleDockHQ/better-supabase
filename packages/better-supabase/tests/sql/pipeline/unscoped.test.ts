import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/index.ts";
import {
  takeUnscoped,
  UNSCOPED_MODULE,
} from "../../../src/sql/pipeline/unscoped.ts";

describe("takeUnscoped", () => {
  it("takes event triggers and triggers on auth tables with their comments", () => {
    const sql = `create table t (id int);
-- Keeps the email in step.
create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function f();
create event trigger bsb_x on sql_drop
  execute function g();
create trigger bsb_audit after insert on public.t for each row execute function h();
`;

    const { rest, statements } = takeUnscoped(sql);

    expect(statements).toHaveLength(2);
    expect(statements[0]).toContain("-- Keeps the email in step.");
    expect(rest).toContain("create table t");
    expect(rest).toContain("on public.t");
    expect(rest).not.toContain("auth.users");
    expect(rest).not.toContain("event trigger");
  });

  it("leaves text without them as it is", () => {
    expect(takeUnscoped("select 1;\n")).toEqual({
      rest: "select 1;\n",
      statements: [],
    });
  });
});

describe("the unscoped file", () => {
  const unscoped = (names: string[], layout = {}) =>
    renderBlocks(names, layout).find((file) => file.module === UNSCOPED_MODULE);

  it("holds the audit event trigger and the profile triggers on auth.users", () => {
    const file = unscoped(["audit", "profiles"]);

    expect(file?.path).toBe(
      "supabase/schemas/900_better_supabase_999_unscoped.sql",
    );
    expect(file?.contents).toContain("@bsb-block unscoped@1 managed");
    expect(file?.contents).toContain(
      "create event trigger bsb_audit_forget_dropped",
    );
    expect(file?.contents).toContain("on auth.users");
  });

  it("takes them out of the module files", () => {
    const module = renderBlocks(["audit"])
      .filter((file) => file.kind === "schema" && file.module === "audit")
      .map((file) => file.contents)
      .join("\n");

    expect(module).not.toContain("create event trigger");
  });

  it("declares event triggers without a drop statement", () => {
    const file = unscoped(["audit", "rls-guard"]);

    expect(file?.contents).toContain("create event trigger");
    expect(file?.contents).not.toMatch(/^drop /mu);
  });

  it("writes no file without such a statement", () => {
    expect(unscoped(["tags"])).toBeUndefined();
  });

  it("keeps them in the module for the migrations workflow", () => {
    expect(unscoped(["audit"], { rerunnable: true })).toBeUndefined();
  });
});
