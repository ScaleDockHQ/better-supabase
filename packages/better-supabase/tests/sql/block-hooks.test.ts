import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { moduleBody } from "../../src/sql/render.ts";
import { moduleProvider } from "../fixtures/authorization-provider.ts";

/**
 * The SQL hooks each extensible block calls around its writes, named
 * `before_<entity>_<action>` and `after_<entity>_<action>` (ADR 0015).
 * `after_notify` predates the convention and keeps its name.
 */
const REQUIRED: Readonly<Record<string, readonly string[]>> = {
  organizations: [
    "before_organization_create",
    "after_organization_create",
    "before_organization_update",
    "after_organization_update",
  ],
  profiles: ["before_profile_update", "after_profile_update"],
  notifications: ["before_notification_send", "after_notify"],
  "number-sequences": ["before_number_assign", "after_number_assign"],
  teams: ["before_team_create", "after_team_create"],
  tags: ["before_tag_apply", "after_tag_apply"],
  versions: [
    "before_version_snapshot",
    "after_version_snapshot",
    "before_version_restore",
    "after_version_restore",
  ],
};

const NAMING = /^(before|after)_[a-z]+(_[a-z]+)*$/;

describe.each(Object.entries(REQUIRED))(
  "block SQL hooks of %s",
  (module, hooks) => {
    const declared = SQL_MODULES[module]?.names?.hooks ?? [];
    const sql = moduleBody(module, {
      modules: {},
      accessProvider: moduleProvider,
    });

    it.each(hooks)("declares and calls %s", (hook) => {
      expect(declared).toContain(hook);
      expect(sql).toContain(`"public"."${hook}"(`);
    });

    it("names its before and after hooks by the convention", () => {
      const lifecycle = declared.filter((hook) =>
        /^(before|after)_/.test(hook),
      );
      expect(lifecycle.filter((hook) => !NAMING.test(hook))).toEqual([]);
    });
  },
);
