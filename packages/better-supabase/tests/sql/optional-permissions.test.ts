import { readFileSync, readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { checkFormerPermissionKeys } from "../../src/config/former-permission-keys.ts";
import { modulePermissionKeys } from "../../src/sql/introspect.ts";
import {
  isOperationModule,
  moduleOperations,
} from "../../src/sql/modules/permissions-model.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const MODULES_DIR = new URL("../../src/sql/modules/", import.meta.url);

// Every camelCase string literal in the modules: a superset of the actions any
// module reads from `blocks.<module>.permissions`.
const CANDIDATES = [
  ...new Set(
    readdirSync(MODULES_DIR).flatMap((file) =>
      [
        ...readFileSync(new URL(file, MODULES_DIR), "utf-8").matchAll(
          /"([a-z][A-Za-z]{1,40})"/gu,
        ),
      ].map((match) => match[1]!),
    ),
  ),
];

// Modules that do not render without more of the config than permissions.
const NEEDS_MORE_CONFIG = new Set(["entitlements"]);

const isFormer = (module: string, action: string): boolean => {
  try {
    checkFormerPermissionKeys("blocks", module, { [action]: true });

    return false;
  } catch {
    return true;
  }
};

describe("OPTIONAL_MODULE_PERMISSIONS", () => {
  it.each(Object.keys(SQL_MODULES).filter((m) => !NEEDS_MORE_CONFIG.has(m)))(
    "lists every permission action the %s SQL checks",
    (name) => {
      const permissions = Object.fromEntries(
        CANDIDATES.filter((action) => !isFormer(name, action)).map((action) => [
          action,
          `probe.${action}`,
        ]),
      );

      const modules = { [name]: { permissions } };

      const sql = renderBlocks([name], { modules })
        .map((file) => file.contents)
        .join("\n");

      const checked = new Set(
        [...sql.matchAll(/'probe\.([A-Za-z]+)'/gu)].map((match) => match[1]!),
      );

      const listed = new Set([
        ...modulePermissionKeys(modules, [name])
          .filter((key) => key.module === name)
          .map((key) => key.action),
        // The operation lookup names every operation, also ones this config
        // leaves unused.
        ...(isOperationModule(name) ? Object.keys(moduleOperations(name)) : []),
      ]);

      expect([...checked].filter((action) => !listed.has(action))).toEqual([]);
    },
  );
});
