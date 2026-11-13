import { describe, expect, it } from "vitest";

import {
  declaredPermissions,
  permissionArea,
  permissionKeyProblem,
  PERMISSION_VERBS,
} from "../../src/blocks/permission-keys.ts";
import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { OPERATIONS } from "../../src/sql/modules/permissions-model.ts";

const LEGACY: ReadonlySet<string> = new Set(Object.values(OPERATIONS));

describe("permissionKeyProblem", () => {
  it("accepts <block>.<entity>.<verb>", () => {
    expect(
      permissionKeyProblem("risks", "risk", "read", "risks.risk.read", LEGACY),
    ).toBeUndefined();

    expect(
      permissionKeyProblem(
        "api-keys",
        "api_key",
        "rotate",
        "api_keys.api_key.rotate",
        LEGACY,
      ),
    ).toBeUndefined();
  });

  it("rejects a key that names another block, entity or verb", () => {
    expect(
      permissionKeyProblem("risks", "risk", "read", "tasks.risk.read", LEGACY),
    ).toContain("risks.risk.read");

    expect(
      permissionKeyProblem("risks", "risk", "read", "risks.risk.view", LEGACY),
    ).toContain("risks.risk.read");
  });

  it("rejects a key with the wrong shape and a verb that is not snake_case", () => {
    expect(
      permissionKeyProblem("risks", "risk", "read", "risks", LEGACY),
    ).toContain("<block>.<entity>.<verb>");

    expect(
      permissionKeyProblem(
        "risks",
        "risk",
        "readAll",
        "risks.risk.readAll",
        LEGACY,
      ),
    ).toContain("snake_case");
  });

  it("accepts a two-part key only when a module already checks it", () => {
    expect(
      permissionKeyProblem(
        "leave",
        "leave_request",
        "read",
        "leave.read",
        LEGACY,
      ),
    ).toBeUndefined();

    expect(
      permissionKeyProblem(
        "leave",
        "leave_request",
        "read",
        "leave.peek",
        LEGACY,
      ),
    ).toContain("<block>.<entity>.<verb>");
  });
});

describe("the permissions the manifests declare", () => {
  it("names each verb in snake_case and each key in the known shapes", () => {
    const problems = BLOCK_MANIFESTS.flatMap((block) =>
      declaredPermissions(block.entities).flatMap(({ entity, verb, key }) => {
        const problem = permissionKeyProblem(
          block.name,
          entity,
          verb,
          key,
          LEGACY,
        );

        return problem === undefined
          ? []
          : [`${block.name}.${entity}: ${problem}`];
      }),
    );

    expect(problems).toStrictEqual([]);
  });

  it("declares only entities the block has", () => {
    expect(
      BLOCK_MANIFESTS.filter(
        (block) => declaredPermissions(block.entities).length > 0,
      )
        .map((block) => block.name)
        .toSorted(),
    ).toStrictEqual([
      "advisories",
      "commissions",
      "deadlines",
      "field-encryption",
      "leave",
      "periods",
      "referrals",
    ]);
  });
});

describe("permission verbs", () => {
  it("lists the fixed verbs", () => {
    expect(PERMISSION_VERBS).toStrictEqual([
      "read",
      "create",
      "update",
      "archive",
      "delete",
      "export",
      "import",
      "manage",
    ]);
  });

  it("writes a block name as its key area", () => {
    expect(permissionArea("api-keys")).toBe("api_keys");
  });
});
