import { describe, expect, it } from "vitest";

import { applyPatch } from "../../../src/blocks/sso/scim-patch.ts";
import {
  ATTRIBUTES,
  SCIM_GROUP,
  SCIM_PATCH,
  SCIM_USER,
} from "../../../src/blocks/sso/scim-schema.ts";

const user = {
  schemas: [SCIM_USER],
  id: "u1",
  userName: "bjensen",
  name: { givenName: "Barbara", familyName: "Jensen" },
  emails: [
    { value: "b@work.test", type: "work", primary: true },
    { value: "b@home.test", type: "home" },
  ],
  active: true,
};

const patchUser = (...operations: unknown[]) =>
  applyPatch(
    user,
    { schemas: [SCIM_PATCH], Operations: operations },
    SCIM_USER,
    ATTRIBUTES.User,
    SCIM_PATCH,
  );

describe("applyPatch", () => {
  it("leaves the input untouched", () => {
    patchUser({ op: "replace", path: "userName", value: "x" });
    expect(user.userName).toBe("bjensen");
  });

  it("adds and replaces singular and complex attributes", () => {
    expect(
      patchUser(
        { op: "add", path: "name", value: { formatted: "B J" } },
        { op: "replace", path: "name.familyName", value: "J" },
        { op: "add", path: "displayName", value: "Babs" },
      ),
    ).toMatchObject({
      name: { givenName: "Barbara", familyName: "J", formatted: "B J" },
      displayName: "Babs",
    });
    expect(
      patchUser({ op: "replace", path: "name", value: { givenName: "B" } })[
        "name"
      ],
    ).toEqual({
      givenName: "B",
    });
    expect(patchUser({ op: "remove", path: "name.givenName" })["name"]).toEqual(
      {
        familyName: "Jensen",
      },
    );
    expect(patchUser({ op: "remove", path: "name" })["name"]).toBeUndefined();
  });

  it("works on multi-valued attributes with and without filters", () => {
    const emails = (doc: Record<string, unknown>) =>
      doc["emails"] as Record<string, unknown>[];
    expect(
      emails(
        patchUser({
          op: "add",
          path: "emails",
          value: { value: "B@WORK.TEST" },
        }),
      ),
    ).toHaveLength(2);
    expect(
      emails(
        patchUser({
          op: "add",
          path: "emails",
          value: [{ value: "c@x.test", primary: true }],
        }),
      ).map((e) => e["primary"]),
    ).toEqual([false, undefined, true]);
    expect(
      emails(
        patchUser({
          op: "replace",
          path: "emails",
          value: [{ value: "only@x.test" }],
        }),
      ),
    ).toEqual([{ value: "only@x.test" }]);
    expect(
      emails(
        patchUser({ op: "replace", path: "emails.type", value: "other" }),
      ).map((e) => e["type"]),
    ).toEqual(["other", "other"]);
    expect(
      emails(patchUser({ op: "remove", path: "emails.primary" })).map(
        (e) => e["primary"],
      ),
    ).toEqual([undefined, undefined]);
    expect(
      emails(
        patchUser({
          op: "replace",
          path: 'emails[type eq "home"]',
          value: { value: "n@home.test" },
        }),
      ),
    ).toEqual([user.emails[0], { value: "n@home.test" }]);
    expect(
      emails(
        patchUser({
          op: "add",
          path: 'emails[type eq "home"]',
          value: { display: "Home" },
        }),
      )[1],
    ).toEqual({ value: "b@home.test", type: "home", display: "Home" });
    expect(
      emails(
        patchUser({ op: "remove", path: 'emails[type eq "work"].primary' }),
      )[0],
    ).toEqual({ value: "b@work.test", type: "work" });
    expect(
      patchUser({ op: "remove", path: "emails" })["emails"],
    ).toBeUndefined();

    const empty = applyPatch(
      { schemas: [SCIM_USER], userName: "x" },
      {
        schemas: [SCIM_PATCH],
        Operations: [{ op: "add", path: "emails.value", value: "x@y.test" }],
      },
      SCIM_USER,
      ATTRIBUTES.User,
      SCIM_PATCH,
    );
    expect(empty["emails"]).toEqual([{ value: "x@y.test" }]);
  });

  it("applies attribute objects without a path, including the schema URN", () => {
    expect(
      patchUser({
        op: "replace",
        value: {
          schemas: [SCIM_USER],
          [SCIM_USER]: { displayName: "Babs" },
          "name.givenName": "B",
          Active: false,
        },
      }),
    ).toMatchObject({
      displayName: "Babs",
      name: { givenName: "B" },
      active: false,
    });
  });

  it("patches group members by value", () => {
    const group = {
      schemas: [SCIM_GROUP],
      displayName: "Admins",
      members: [{ value: "u1" }],
    };
    const result = applyPatch(
      group,
      {
        schemas: [SCIM_PATCH],
        Operations: [
          {
            op: "add",
            path: "members",
            value: [{ value: "u2" }, { value: "u3" }],
          },
          { op: "remove", path: "members", value: [{ value: "u1" }] },
          { op: "remove", path: 'members[value eq "u3"]' },
        ],
      },
      SCIM_GROUP,
      ATTRIBUTES.Group,
      SCIM_PATCH,
    );
    expect(result["members"]).toEqual([{ value: "u2" }]);
  });

  it.each([
    [{}, "invalidSyntax"],
    [{ schemas: [SCIM_PATCH] }, "invalidSyntax"],
    [{ schemas: [SCIM_PATCH], Operations: ["x"] }, "invalidSyntax"],
    [
      { schemas: [SCIM_PATCH], Operations: [{ op: "add", path: 5, value: 1 }] },
      "invalidPath",
    ],
    [
      {
        schemas: [SCIM_PATCH],
        Operations: [{ op: "add", path: "bad path!", value: 1 }],
      },
      "invalidPath",
    ],
    [
      {
        schemas: [SCIM_PATCH],
        Operations: [{ op: "add", path: "name", value: "x" }],
      },
      "invalidValue",
    ],
    [
      {
        schemas: [SCIM_PATCH],
        Operations: [
          { op: "replace", path: 'emails[type eq "work"]', value: "x" },
        ],
      },
      "invalidValue",
    ],
  ])("rejects %j", (body, scimType) => {
    expect(() =>
      applyPatch(user, body, SCIM_USER, ATTRIBUTES.User, SCIM_PATCH),
    ).toThrow(expect.objectContaining({ scimType }));
  });
});
