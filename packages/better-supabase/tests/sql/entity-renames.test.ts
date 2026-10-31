import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { resolveConfig } from "../../src/config/resolve.ts";
import { pluralOf } from "../../src/core/entity-naming.ts";
import { entityRenamePlan, renderBlocks } from "../../src/sql/index.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const BLOCKS = ["memberships", "permissions", "outbox", "tasks"];

const TASKS: BlockSqlLayout = {
  modules: { tasks: { entities: { task: "ticket", project: "initiative" } } },
};

const body = (module: string, layout: BlockSqlLayout): string =>
  renderBlocks(BLOCKS, layout)
    .filter((file) => file.module === module && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("blocks.<name>.entities in the SQL", () => {
  it("renames tables, functions, events, permission keys and hooks", () => {
    const sql = body("tasks", TASKS);

    expect(sql).toContain(
      'create table if not exists "better_supabase"."tickets"',
    );
    expect(sql).toContain('"better_supabase"."initiatives"');
    expect(sql).toContain('"better_supabase"."create_ticket"(');
    expect(sql).toContain("'ticket.created'");
    expect(sql).toContain("'tickets/'");
    expect(sql).toContain("'ticketId'");
    expect(sql).toContain("'tasks.read'");
    expect(sql).toContain('"public"."before_ticket_create"(');
    expect(sql).toContain(
      "-- @bsb-names tasks task=ticket/tickets project=initiative/initiatives",
    );
  });

  it("writes the default names and no marker without entities", () => {
    const sql = body("tasks", {});

    expect(sql).toContain('"better_supabase"."tasks"');
    expect(sql).toContain('"better_supabase"."create_task"(');
    expect(sql).toContain("'task.created'");
    expect(sql).not.toContain("@bsb-names");
  });

  it("renames the default roles' keys after every block's entities", () => {
    expect(body("permissions", TASKS)).toContain("'tasks.*'");
    expect(body("permissions", {})).toContain("'tasks.*'");
  });

  it("keeps the tenant rename out of events, permission keys and hooks", () => {
    const sql = body("tasks", {
      modules: { memberships: { entities: { organization: "workspace" } } },
    });

    expect(sql).toContain("'task.created'");
    expect(sql).toContain("'organizationId'");
    expect(sql).toContain("'tasks.read'");
  });

  it("leaves the default nouns only in parameter names, hints and prose", () => {
    const modules = {
      tasks: {
        entities: { task: "ticket", project: "initiative", iteration: "cycle" },
      },
    } as const;

    const names = [...BLOCKS, "pipelines", "rank", "subjects", "notifications"];

    const layout: BlockSqlLayout = {
      modules,
      subjects: withBlockSubjects({}, names, modules),
    };

    const parameter =
      /\b(?:\w+\.)?(?:work_item|project|iteration)\b(?= uuid|[^_\w'"]|$)/g;

    const left = renderBlocks(names, layout)
      .flatMap((file) => file.contents.split("\n"))
      .filter((line) => !line.trimStart().startsWith("--"))
      .map((line) =>
        line.replaceAll(/'[^']*\s[^']*'/g, "").replaceAll(parameter, ""),
      )
      .filter((line) =>
        /work_?items?|workItem|\btasks?_|projects?(?:_id|Id)|iterations?(?:_id|Id)/.test(
          line,
        ),
      );

    expect(left).toEqual([]);
  });

  // JSON payload keys the TypeScript client reads, ledger account keys stored
  // in rows, option defaults and columns another block owns keep their names.
  const CONTRACT: Readonly<Record<string, readonly string[]>> = {
    catalog: ["'productId'", "'variantId'"],
    announcements: ["'announcement_changed'"],
    automations: ["'rules'", "'rules[]'", '"rules"', "'ruleId'"],
    hiring: ["'interviews[]'", "'interviews'"],
    inbox: ["'inbox_id'"],
    inventory: ["'purchaseOrderId'"],
    manufacturing: [
      "'bomId'",
      "'workCenterId'",
      "'productionOrders'",
      "'purchaseOrders'",
    ],
    invoices: [
      "'invoices:cash:",
      "'invoices:credit:",
      "'invoice_party'",
      "'invoiceId'",
    ],
    medications: ["'medication'", "'medicationId'"],
    meetings: ["'meetingId'"],
    memory: ["'/memories'", "'/memories{}'"],
    orders: ["'cartId'", "'orderId'"],
    promotions: ['"promotions"', "'promotionId'"],
  };

  const renamable = Object.entries(SQL_MODULES).flatMap(([name, module]) => {
    const entities = Object.entries(module.names?.entities ?? {}).filter(
      ([, entity]) => !entity.global,
    );

    return entities.length === 0 || name === "memberships"
      ? []
      : [[name, entities] as const];
  });

  it.each(renamable)(
    "renames every %s identifier with its entities",
    (name, entities) => {
      const modules = {
        [name]: {
          entities: Object.fromEntries(
            entities.map(([key], index) => [
              key,
              `zq${"abcdefgh".charAt(index)}`,
            ]),
          ),
        },
      };

      const layout: BlockSqlLayout = {
        modules,
        subjects: withBlockSubjects({}, [name], modules),
      };

      const camel = (value: string): string =>
        value.replaceAll(/_([a-z])/g, (_, letter: string) =>
          letter.toUpperCase(),
        );

      const nouns = entities.flatMap(([, entity]) => [
        {
          singular: entity.singular,
          plural: entity.plural ?? pluralOf(entity.singular),
        },
        ...(entity.formerly === undefined
          ? []
          : [{ singular: entity.formerly, plural: pluralOf(entity.formerly) }]),
      ]);

      // Parameter names keep the default nouns (`document`, `document_id`).
      const parameter = new RegExp(
        String.raw`\b(?:\w+\.)?(?:${nouns.map((noun) => noun.singular).join("|")})(?:_id)?\b(?= uuid|[^_\w'"]|$)`,
        "g",
      );

      const leftover = new RegExp(
        String.raw`(?<![a-zA-Z])(?:${nouns
          .flatMap(({ singular, plural }) => [
            String.raw`${plural}(?![a-z])`,
            camel(plural),
            `${singular}_`,
            `${camel(singular)}Id`,
          ])
          .join("|")})`,
      );

      const files = renderBlocks([name], layout);

      const declared = new RegExp(
        String.raw`(?<!")\b(?:\w+\.)?(?:${[
          ...new Set(
            files.flatMap((file) =>
              [
                ...file.contents.matchAll(/function [\w".]+\(([^)]*)\)/g),
              ].flatMap((match) =>
                match[1]!
                  .split(",")
                  .map((arg) => arg.trim().split(" ")[0]!)
                  .filter((arg) => /^\w+$/.test(arg)),
              ),
            ),
          ),
          "\\b\\B",
        ].join("|")})\b`,
        "g",
      );

      const left = files
        .flatMap((file) => file.contents.split("\n"))
        .filter((line) => !line.trimStart().startsWith("--"))
        .map((line) =>
          (CONTRACT[name] ?? [])
            .reduce((rest, literal) => rest.replaceAll(literal, ""), line)
            .replaceAll(`'${name}'`, "")
            .replaceAll(`'${name}.`, "'")
            .replaceAll(/'[^']*\s[^']*'/g, "")
            // Block-scoped names (`bsb_attachments_bucket`, storage policies) and
            // storage paths keep the block name, so existing objects match.
            .replaceAll(
              new RegExp(String.raw`bsb_${name}_\w+|/${name}/`, "g"),
              "",
            )
            // The default privileges name every object kind, not an entity.
            .replaceAll(
              /alter default privileges in schema \w+ revoke all on \w+ from[^;]*;/g,
              "",
            )
            // Supabase owns `realtime.messages`.
            .replaceAll("realtime.messages", "")
            // Realtime topic prefixes are option values (`options.topic`).
            .replaceAll(/'[a-z][a-z0-9_-]*:%?'/g, "")
            .replaceAll(/\bv_\w+/g, "")
            .replaceAll(parameter, "")
            .replaceAll(declared, ""),
        )
        .filter((line) => leftover.test(line));

      expect(left).toEqual([]);
    },
  );

  it("refuses a rename onto another block's table", () => {
    expect(() =>
      renderBlocks([...BLOCKS, "deals"], {
        modules: { tasks: { entities: { task: "deal" } } },
      }),
    ).toThrow(
      "blocks.tasks.names: the tasks block's items table would be named deals, which the deals block already uses",
    );
  });
});

describe("entityRenamePlan", () => {
  const installed = renderBlocks(BLOCKS, {});
  const text = installed.map((file) => file.contents).join("\n");
  const modules = [...new Set(installed.map((file) => file.module))];

  const sql = (layout: BlockSqlLayout): string[] =>
    entityRenamePlan(BLOCKS, modules, text, layout).steps.map(
      (step) => step.sql,
    );

  it("renames the tables, columns and functions of a changed block", () => {
    const plan = entityRenamePlan(BLOCKS, modules, text, TASKS);

    expect(plan.refused).toEqual([]);
    // The pipelines module's triggers on the renamed table move with it.
    expect(new Set(plan.steps.map((step) => step.module))).toEqual(
      new Set(["tasks", "pipelines"]),
    );
    expect(sql(TASKS)).toEqual(
      expect.arrayContaining([
        expect.stringContaining(
          'alter table "better_supabase"."tasks" rename to "tickets"',
        ),
        expect.stringContaining(
          'alter table "better_supabase"."projects" rename to "initiatives"',
        ),
        expect.stringContaining("'create_ticket')"),
      ]),
    );
  });

  it("guards every rename so a second run changes nothing", () => {
    for (const statement of sql(TASKS)) {
      expect(statement).toMatch(/^do \$\$|if exists|^update /);
    }
  });

  it("moves stored subjects to the renamed type", () => {
    const blocks = [...BLOCKS, "subjects", "messaging", "comments"];

    const before = renderBlocks(blocks, {
      subjects: withBlockSubjects({}, ["tasks"], {}),
    });

    const after = TASKS.modules!;

    const steps = entityRenamePlan(
      blocks,
      [...new Set(before.map((file) => file.module))],
      before.map((file) => file.contents).join("\n"),
      { modules: after, subjects: withBlockSubjects({}, ["tasks"], after) },
    ).steps.map((step) => step.sql);

    expect(steps).toContain(
      `update "better_supabase"."conversations" set "subject_type" = 'ticket' where "subject_type" = 'task';`,
    );
  });

  it("plans nothing when the names didn't change", () => {
    expect(sql({})).toEqual([]);
  });

  it("reads a 0.46 marker's entity keys at their 0.47 key", () => {
    const renamed = renderBlocks(BLOCKS, TASKS)
      .map((file) => file.contents)
      .join("\n")
      .replace("@bsb-names tasks task=", "@bsb-names tasks work_item=");

    expect(entityRenamePlan(BLOCKS, modules, renamed, TASKS).steps).toEqual([]);
  });

  it("keeps an instance whose 0.46 marker names the same entities", () => {
    const config = resolveConfig(
      {
        blocks: {
          tasks: {},
          facilities: { block: "tasks", entities: { task: "request" } },
        },
      },
      "/app",
    );

    const layout = moduleLayout(config);

    const installed = renderBlocks(config.blockNames, layout)
      .map((file) => file.contents)
      .join("\n")
      .replace(
        "@bsb-names facilities task=",
        "@bsb-names facilities work_item=",
      );

    expect(installed).toContain("@bsb-names facilities work_item=");
    expect(
      entityRenamePlan(
        config.blockNames,
        [...config.blockNames, "facilities"],
        installed,
        layout,
      ),
    ).toEqual({ steps: [], refused: [] });
  });

  it("plans the way back from the installed names", () => {
    const renamed = renderBlocks(BLOCKS, TASKS);

    expect(
      entityRenamePlan(
        BLOCKS,
        modules,
        renamed.map((file) => file.contents).join("\n"),
        {},
      ).steps.map((step) => step.sql),
    ).toEqual(
      expect.arrayContaining([
        expect.stringContaining(
          'alter table "better_supabase"."tickets" rename to "tasks"',
        ),
      ]),
    );
  });
});
