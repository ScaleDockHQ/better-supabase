import { describe, expect, it } from "vitest";

import {
  auditExemptTag,
  grantTag,
  lifecycleTag,
  sameTenantTag,
  splitList,
} from "../../src/sql/table-facts.ts";

describe("splitList", () => {
  it("splits at commas outside parentheses", () => {
    expect(splitList("select, update(title, body),delete")).toEqual([
      "select",
      "update(title, body)",
      "delete",
    ]);
  });
});

describe("auditExemptTag", () => {
  it("reads the reason, and a bare tag has none", () => {
    expect(
      auditExemptTag('@bsb audit-exempt reason="rebuilt nightly"'),
    ).toEqual({ reason: "rebuilt nightly" });
    expect(auditExemptTag("@bsb audit-exempt")).toEqual({ reason: undefined });
    expect(auditExemptTag("Free text only")).toBeUndefined();
    expect(auditExemptTag(null)).toBeUndefined();
  });
});

describe("lifecycleTag", () => {
  it("reads user, tenant, flags and omitted columns", () => {
    expect(
      lifecycleTag(
        "@bsb data-lifecycle user=owner_id tenant=org_id export=false purge=true omit=secret,token",
      ),
    ).toEqual({
      user: "owner_id",
      tenant: "org_id",
      export: false,
      purge: true,
      omit: ["secret", "token"],
    });
    expect(lifecycleTag("@bsb subject")).toBeUndefined();
  });

  it("refuses a flag that is not true or false", () => {
    expect(() =>
      lifecycleTag("@bsb data-lifecycle user=a purge=maybe"),
    ).toThrow("must be true or false");
  });
});

describe("grantTag", () => {
  it("reads each role's privileges, with column lists", () => {
    expect(
      grantTag(
        '@bsb grant authenticated="select,update(title, body)" anon=select service-role=select',
      ),
    ).toEqual({
      authenticated: ["select", "update(title, body)"],
      anon: ["select"],
      serviceRole: ["select"],
    });
    expect(grantTag("@bsb subject")).toBeUndefined();
  });
});

describe("sameTenantTag", () => {
  it("reads where, match and through, and the opt-out", () => {
    expect(
      sameTenantTag(
        "@bsb same-tenant where=\"{row}.kind = 'a'\" match=region=region,owner.team=team through=owner=public.owners",
      ),
    ).toEqual({
      where: "{row}.kind = 'a'",
      match: { region: "region", "owner.team": "team" },
      through: { owner: "public.owners" },
    });
    expect(sameTenantTag("@bsb same-tenant")).toEqual({});
    expect(sameTenantTag("@bsb same-tenant=false")).toEqual({ skip: true });
    expect(sameTenantTag("nothing")).toBeUndefined();
  });
});
