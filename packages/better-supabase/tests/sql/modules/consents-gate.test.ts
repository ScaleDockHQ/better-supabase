import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const render = (module: string, blocks: readonly string[]): string =>
  renderBlocks(blocks, { modules: {} })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("the consent gate", () => {
  it("renders requires_consent for users and consent_missing for the service", () => {
    const sql = render("consents", ["consents"]);

    expect(sql).toContain('"better_supabase"."requires_consent"');
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."?consent_missing"?\([^)]*\) to service_role;/,
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."?consent_missing"?\([^)]*\) to [^;]*authenticated/,
    );
  });

  it("seeds the purposes that installed blocks contribute as system purposes", () => {
    const sql = render("consents", ["consents", "sequences", "notifications"]);

    expect(sql).toContain("'outreach_email'");
    expect(sql).toContain("'notification_email'");
    expect(sql).toContain("on conflict do nothing");
  });

  it("seeds no purposes without contributions", () => {
    expect(render("consents", ["consents"])).not.toContain("'outreach_email'");
  });

  it("skips a sequence email step whose consent is missing", () => {
    const sql = render("sequences", ["consents", "sequences"]);

    expect(sql).toContain("consentPurpose");
    expect(sql).toMatch(/consent_missing/);
  });

  it("leaves sequences ungated without the consents block", () => {
    expect(render("sequences", ["sequences"])).not.toContain("consent_missing");
  });

  it("returns null from send_notification while the purpose has no consent", () => {
    const sql = render("notifications", ["consents", "notifications"]);

    expect(sql).toContain("notification ->> 'consent_purpose'");
    expect(sql).toContain("consent_missing");
    expect(render("notifications", ["notifications"])).not.toContain(
      "consent_missing",
    );
  });
});
