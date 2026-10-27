import { describe, expect, it } from "vitest";

import { triggerFills } from "../../../src/cli/introspect/trigger-fills.ts";

describe("triggerFills", () => {
  it("reads assignments on new", () => {
    expect(
      triggerFills(
        "plpgsql",
        `begin
          new.kvk := coalesce(new.kvk, 'n/a');
          if new.name is null then new.Name = 'x'; end if;
          new."Display" := 'y';
          return new;
        end`,
      ),
    ).toEqual(["Display", "kvk", "name"]);
  });

  it("reads an assignment that follows a label", () => {
    expect(
      triggerFills(
        "plpgsql",
        "begin <<fill>> new.slug := 'a'; return new; end",
      ),
    ).toEqual(["slug"]);
  });

  it("reads select into new columns", () => {
    expect(
      triggerFills(
        "plpgsql",
        "begin select a, b into strict new.owner_id, new.tenant_id from t; return new; end",
      ),
    ).toEqual(["owner_id", "tenant_id"]);
  });

  it("ignores comparisons, comments and strings", () => {
    expect(
      triggerFills(
        "plpgsql",
        `begin
          -- new.kvk := 'commented';
          if new.kvk = '' then raise exception 'new.kvk := missing'; end if;
          return new;
        end`,
      ),
    ).toEqual([]);
  });

  it("is unknown for a whole-row assignment or another language", () => {
    expect(
      triggerFills("plpgsql", "begin new := old; return new; end"),
    ).toBeUndefined();
    expect(
      triggerFills(
        "plpgsql",
        "begin select * into new from t; return new; end",
      ),
    ).toBeUndefined();
    expect(triggerFills("sql", "select 1")).toBeUndefined();
  });
});
