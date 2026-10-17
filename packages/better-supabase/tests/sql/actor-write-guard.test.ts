import { describe, expect, it } from "vitest";

import { WRITE_GUARD_ALLOWLIST } from "../../src/sql/actor-guard.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderModules } from "../../src/sql/render.ts";

const WRITE = /\b(insert\s+into|update\s+(?:only\s+)?["a-z_]|delete\s+from)\b/i;

/** User-callable security-definer functions whose body writes and has no guard. */
function unguardedWrites(sql: string): string[] {
  const granted = new Set<string>();

  for (const match of sql.matchAll(
    /grant\s+execute\s+on\s+function\s+((?:"[^"]+"|[a-z_][\w$]*)(?:\s*\.\s*(?:"[^"]+"|[a-z_][\w$]*))?)\s*\([^;]*?\)\s+to\s+([^;]+)/gi,
  )) {
    if (!/\b(authenticated|anon)\b/i.test(match[2] ?? "")) {
      continue;
    }

    const name = /(?:"([^"]+)"|([a-z_][\w$]*))\s*$/i.exec(match[1] ?? "");
    const found = name?.[1] ?? name?.[2];

    if (found !== undefined) {
      granted.add(found);
    }
  }

  const missing: string[] = [];

  for (const match of sql.matchAll(
    /create\s+(?:or\s+replace\s+)?function\s+/gi,
  )) {
    const at = match.index;
    const tagged = /as\s+(\$[a-zA-Z0-9_]*\$)/i.exec(sql.slice(at));

    if (tagged === null) {
      continue;
    }

    const header = sql.slice(at, at + tagged.index);
    const bodyStart = at + tagged.index + tagged[0].length;
    const bodyEnd = sql.indexOf(tagged[1] ?? "$$", bodyStart);

    if (bodyEnd === -1) {
      continue;
    }

    const name =
      /function\s+(?:(?:"[^"]+"|[a-z_][\w$]*)\s*\.\s*)?(?:"([^"]+)"|([a-z_][\w$]*))\s*\(/i.exec(
        header,
      );

    const found = name?.[1] ?? name?.[2];

    if (found === undefined || !granted.has(found)) {
      continue;
    }

    if (WRITE_GUARD_ALLOWLIST.has(found)) {
      continue;
    }

    if (!/\bsecurity\s+definer\b/i.test(header)) {
      continue;
    }

    const body = sql.slice(bodyStart, bodyEnd);

    if (
      WRITE.test(body) &&
      !body.includes("ACTOR_READ_ONLY") &&
      !body.includes("raise_actor_readonly()")
    ) {
      missing.push(found);
    }
  }

  return [...new Set(missing)].toSorted();
}

describe("actor write guard", () => {
  const sql = renderModules([
    "profiles",
    "notifications",
    "teams",
    "tags",
    "share-links",
    "number-sequences",
  ])
    .map((file) => file.contents)
    .join("\n");

  it("refuses a read-only actor inside user-granted writes", () => {
    expect(sql).toContain("ACTOR_READ_ONLY");
    expect(sql).toContain("better_supabase.actor_may_write()");
  });

  it("guards every authenticated write except the session allowlist", () => {
    const sql = renderModules(
      Object.values(SQL_MODULES)
        .filter((module) => module.target === "schema")
        .map((module) => module.name),
    )
      .map((file) => file.contents)
      .join("\n");

    expect(unguardedWrites(sql)).toEqual([]);
  });

  it("gives authenticated no permissive for-all policy, which would skip the guard", () => {
    const sql = renderModules(
      Object.values(SQL_MODULES)
        .filter((module) => module.target === "schema")
        .map((module) => module.name),
    )
      .map((file) => file.contents)
      .join("\n");

    const permissive = [...sql.matchAll(/create\s+policy\b[\s\S]*?;/gi)]
      .map((match) => match[0])
      .filter(
        (statement) =>
          /\bfor\s+all\b/i.test(statement) &&
          !/\bas\s+restrictive\b/i.test(statement) &&
          /\bto\s+[^;]*\bauthenticated\b/i.test(statement),
      );

    expect(permissive).toEqual([]);
  });

  it("guards the split own-row policies on settings and notifications", () => {
    const sql = renderModules(["settings", "notifications"])
      .map((file) => file.contents)
      .join("\n");

    for (const name of [
      "user_settings_own_update",
      "bs_notification_subscriptions_own_insert",
      "bs_notification_preferences_own_delete",
    ]) {
      const statement = new RegExp(`create policy "?${name}"?[^;]*;`, "i").exec(
        sql,
      )?.[0];

      expect(statement).toContain("actor_may_write()");
    }

    expect(
      /create policy "?user_settings_own_read"?[^;]*;/i.exec(sql)?.[0],
    ).not.toContain("actor_may_write()");
  });

  it("keeps the session functions on the allowlist", () => {
    expect([...WRITE_GUARD_ALLOWLIST].toSorted()).toEqual([
      "check_request",
      "end_support_session",
      "expire_support_sessions",
      "start_support_session",
    ]);
  });
});
