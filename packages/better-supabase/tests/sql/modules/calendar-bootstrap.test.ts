import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (blocks: readonly string[]): string =>
  renderBlocks(blocks, {})
    .map((file) => file.contents)
    .join("\n");

describe("calendar_bootstrap", () => {
  it("runs as the caller over the list functions", () => {
    const sql = sqlOf(["calendar"]);
    const start = sql.indexOf(
      'function "better_supabase"."calendar_bootstrap"',
    );
    const body = sql.slice(start, sql.indexOf("$$;", start));

    expect(start).toBeGreaterThan(-1);
    expect(body).toContain("security invoker");
    expect(body).toContain('"list_calendars"');
    expect(body).toContain('"list_calendar_events"');
    expect(body).not.toContain("list_my_reminders");
  });

  it("adds the caller's reminders when the reminders block is installed", () => {
    const sql = sqlOf(["calendar", "reminders"]);
    const start = sql.indexOf(
      'function "better_supabase"."calendar_bootstrap"',
    );
    const body = sql.slice(start, sql.indexOf("$$;", start));

    expect(body).toContain("list_my_reminders");
    expect(body).toContain("'calendar_event'");
    expect(body).toContain("exception when insufficient_privilege");
  });

  it("grants it to signed-in callers only", () => {
    const sql = sqlOf(["calendar"]);

    expect(sql).toMatch(
      /revoke execute on function "better_supabase"\."calendar_bootstrap"\([^)]*\) from public, anon;/u,
    );
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."calendar_bootstrap"\([^)]*\) to authenticated, service_role;/u,
    );
  });
});
