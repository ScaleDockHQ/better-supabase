import { describe, expect, it } from "vitest";

import {
  matchesScimFilter,
  parseScimFilter,
  SCIM_USER,
} from "../../../src/blocks/sso/index.ts";

const user = {
  schemas: [SCIM_USER],
  id: "2819c223-7f76-453a-919d-413861904646",
  externalId: "Ext-1",
  userName: "bjensen@acme.test",
  title: "",
  name: { givenName: "Barbara", familyName: "Jensen" },
  emails: [
    { value: "bjensen@acme.test", type: "work", primary: true },
    { value: "babs@home.test", type: "home" },
  ],
  nickNames: ["Babs"],
  logins: 3,
  active: true,
  meta: { lastModified: "2026-10-06T12:00:00Z", version: 'W/"3"' },
};

const match = (filter: string): boolean =>
  matchesScimFilter(user, parseScimFilter(filter));

describe("SCIM filters", () => {
  it.each([
    ['userName eq "BJENSEN@acme.test"', true],
    ['userName ne "bjensen@acme.test"', false],
    ['userName co "jensen"', true],
    ['userName sw "bj"', true],
    ['userName ew ".test"', true],
    ['userName gt "a"', true],
    ['userName ge "bjensen@acme.test"', true],
    ['userName lt "a"', false],
    ['userName le "a"', false],
    ['nickName eq "x"', false],
    ['nickName ne "x"', true],
    ["title pr", false],
    ["userName pr", true],
    ["name pr", false],
    ["emails pr", true],
    ['externalId eq "ext-1"', false],
    ['externalId eq "Ext-1"', true],
    ['id eq "2819C223-7F76-453A-919D-413861904646"', false],
    ['name.givenName eq "barbara"', true],
    ["name.middleName pr", false],
    ['emails eq "babs@home.test"', true],
    ['emails.type eq "home"', true],
    ['emails[type eq "work" and value co "@acme"]', true],
    ['emails[type eq "other"]', false],
    ['nickNames eq "babs"', true],
    ['nickNames.value eq "babs"', false],
    ["logins gt 2", true],
    ["logins le 2", false],
    ['logins eq "3"', false],
    ["logins eq null", false],
    ["title ne null", true],
    ["active eq true", true],
    ["active ne true", false],
    ['meta.lastModified gt "2026-10-01T00:00:00Z"', true],
    ['meta.lastModified lt "2026-10-01T00:00:00.000+00:00"', false],
    ['meta.version eq "w/\\"3\\""', false],
    [`${SCIM_USER}:userName sw "bj"`, true],
    ['urn:example:Other:userName sw "bj"', false],
    [`schemas eq "${SCIM_USER}"`, true],
    ['not (userName eq "x")', true],
    ['NOT (userName eq "bjensen@acme.test")', false],
    ['userName eq "x" or active eq true and logins gt 5', false],
    ['(userName eq "x" or active eq true) and logins gt 2', true],
    ['userName EQ "bjensen@acme.test" OR userName eq "x"', true],
    ['userName eq "x" or userName eq "y"', false],
    ['name eq "Barbara"', false],
    ["userName co 1", false],
  ])("%s matches %s", (filter, expected) => {
    expect(match(filter)).toBe(expected);
  });

  it.each([
    "",
    'userName eq "open',
    'userName eq "\\x"',
    'userName xx "a"',
    "userName",
    'userName eq "a" and',
    "not userName pr",
    "(userName pr",
    'emails[type eq "work"',
    "userName eq",
    "userName eq word",
    "userName pr extra",
    "1bad pr",
  ])("rejects %j", (filter) => {
    expect(() => parseScimFilter(filter)).toThrow(/./);
  });

  it.each(["active gt false", "logins co 1"])(
    "fails %s on evaluation",
    (filter) => {
      expect(() => match(filter)).toThrow(/applies to strings|booleans/);
    },
  );
});
