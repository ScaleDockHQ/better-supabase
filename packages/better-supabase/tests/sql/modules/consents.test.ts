import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { CONSENTS } from "../../../src/sql/modules/consents.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const render = (also: readonly string[] = []): string =>
  renderBlocks(["consents", ...also], { modules: {} })
    .filter((file) => file.module === "consents")
    .map((file) => file.contents)
    .join("\n");

describe("consents module", () => {
  it("keeps one granted decision per subject and purpose", () => {
    const sql = render();

    expect(sql).toContain(`("subject_type", "subject_id", "purpose_id")`);
    expect(sql).toContain(`where "status" = 'granted'`);
  });

  it("keys a purpose version per organization, with shared system purposes", () => {
    const sql = render();

    expect(sql).toContain(`("tenant_id", "key", "version") nulls not distinct`);
    expect(sql).toMatch(/"tenant_id" is null or/);
  });

  it("grants anon nothing", () => {
    const sql = render();

    const anonGrants = sql
      .split("\n")
      .filter(
        (line) =>
          line.startsWith("grant execute") &&
          line.includes("anon") &&
          !line.includes("actor_"),
      );

    expect(anonGrants).toEqual([]);
    expect(sql).not.toMatch(/create policy [^\n]* to anon/);
  });

  it("leaves expiry to the service role", () => {
    const sql = render();

    expect(sql).toContain(
      `grant execute on function "better_supabase"."expire_consents"() to service_role;`,
    );
    expect(sql).not.toContain("cron.schedule");
  });

  it("checks evidence only against the blocks that are installed", () => {
    expect(render()).not.toContain(`"better_supabase"."signatures"`);

    const sql = render(["signatures", "forms", "attachments"]);

    expect(sql).toContain(`"better_supabase"."signatures"`);
    expect(sql).toContain(`"better_supabase"."attachments"`);
  });

  it("lets representatives act only with the relations block", () => {
    expect(render()).not.toContain("'represents'");
    expect(render(["contacts", "relations", "guests"])).toContain(
      "'represents'",
    );
  });

  it("emits the consent events", () => {
    const sql = render(["outbox"]);

    for (const type of [
      "consent.granted",
      "consent.refused",
      "consent.withdrawn",
      "consent.expired",
      "consent_purpose.created",
      "consent_purpose.updated",
    ]) {
      expect(sql).toContain(`'${type}'`);
    }
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { consents: { mode: "custom" } } };

    const sql = renderBlocks(["consents"], custom)
      .filter((file) => file.module === "consents")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("create table");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(CONSENTS.build(context, {})).toBe("");
    const [contract] = customContracts(["consents"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_consent_purpose",
        "record_consent",
        "withdraw_consent",
        "consent_active",
        "list_consents",
        "expire_consents",
      ]),
    );
  });

  describe("signals and receipts", () => {
    const sql = render();

    it("records Sec-GPC as a refused consent for each purpose", () => {
      expect(sql).toContain("record_consent_signal");
      expect(sql).toContain("'refused'");
    });

    it("parses TCF v2 core segments and GPP headers in the database", () => {
      expect(sql).toContain("parse_tc_string");
      expect(sql).toContain("parse_gpp_string");
      expect(sql).toContain(
        "a TC string is base64url text of at least 36 characters",
      );
    });

    it("issues one receipt per consent and status, with a digest", () => {
      expect(sql).toContain("better-supabase/consent-receipt@1");
      expect(sql).toContain("sha256");
    });

    it("keeps the parsers out of the contract and is a version 2 module", () => {
      expect(CONSENTS.version).toBe(2);
      expect(CONSENTS.internal).toEqual(
        expect.arrayContaining(["parse_tc_string", "parse_gpp_string"]),
      );
    });
  });
});
