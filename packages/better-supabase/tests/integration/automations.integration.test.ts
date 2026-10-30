import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { FilterQuery, FilterRule } from "../../src/list/index.ts";

import {
  createActionRegistry,
  createRuleDispatcher,
  defineAction,
  createAutomations,
  createAutomationsAdmin,
  defineRuleFields,
  evaluateRule,
  sqlTransport,
} from "../../src/blocks/automations/index.ts";
import { ok } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const expenses = defineRuleFields("expense", {
  title: { type: "text" },
  amount: { type: "number", nullable: false },
  status: { type: "select", options: ["draft", "submitted", "paid"] },
  submittedAt: { type: "date" },
  dueOn: { type: "date", columnType: "date" },
  tags: { type: "multiselect" },
  billable: { type: "boolean" },
  approver: { type: "relation", column: "approverId" },
  "submitter.seniority": { type: "select" },
});

const APPROVER = "00000000-0000-4000-8000-0000000000a1";
const now = Temporal.Instant.from("2026-10-13T22:30:00Z");
const timeZone = "Europe/Amsterdam";

const subjects = [
  {
    title: "Flight to Berlin",
    amount: 1250,
    status: "submitted",
    submittedAt: "2026-10-13T08:00:00Z",
    dueOn: "2026-10-20",
    tags: ["travel", "client"],
    billable: true,
    approverId: APPROVER,
    submitter: { seniority: "manager" },
  },
  {
    title: "team lunch",
    amount: "84.5",
    status: "draft",
    submittedAt: null,
    dueOn: null,
    tags: [],
    billable: false,
    approverId: null,
    submitter: { seniority: "junior" },
  },
  {
    title: "Hotel",
    amount: 430,
    status: "paid",
    submittedAt: "2026-10-12T23:30:00Z",
    dueOn: "2026-10-13",
    billable: null,
    submitter: {},
  },
] as const;

let ids = 0;

function rule(
  path: string,
  operator: string,
  value?: unknown,
  negated?: boolean,
): FilterRule {
  ids += 1;

  return {
    id: `r${String(ids)}`,
    type: "rule",
    path: path.split("."),
    operator,
    ...(value === undefined ? {} : { value }),
    ...(negated === undefined ? {} : { negated }),
  };
}

function group(
  rules: FilterQuery["rules"],
  combinator: "and" | "or" = "and",
): FilterQuery {
  ids += 1;

  return { id: `g${String(ids)}`, type: "group", combinator, rules };
}

const day = (date: string) => ({ date });

const CASES: readonly (readonly [string, FilterQuery])[] = [
  ["contains", group([rule("title", "contains", "BERLIN")])],
  ["not_contains", group([rule("title", "not_contains", "lunch")])],
  ["starts_with", group([rule("title", "starts_with", "team")])],
  ["ends_with", group([rule("title", "ends_with", "TEL")])],
  ["text is", group([rule("title", "is", "Hotel")])],
  ["text empty", group([rule("title", "empty")])],
  ["number eq on text", group([rule("amount", "eq", 84.5)])],
  ["number neq", group([rule("amount", "neq", 430)])],
  ["number gt", group([rule("amount", "gt", 500)])],
  ["number gte", group([rule("amount", "gte", 430)])],
  ["number lt", group([rule("amount", "lt", "100")])],
  ["number lte", group([rule("amount", "lte", 430)])],
  ["number between", group([rule("amount", "between", [100, 1000])])],
  ["number between reversed", group([rule("amount", "between", [1000, 100])])],
  ["number not_between", group([rule("amount", "not_between", [100, 1000])])],
  ["select is", group([rule("status", "is", "submitted")])],
  ["select is_not", group([rule("status", "is_not", "submitted")])],
  ["select is_any_of", group([rule("status", "is_any_of", ["draft", "paid"])])],
  ["select is_none_of", group([rule("status", "is_none_of", ["draft"])])],
  ["select empty", group([rule("status", "empty")])],
  ["nested path", group([rule("submitter.seniority", "is", "manager")])],
  [
    "nested path is_not on a missing value",
    group([rule("submitter.seniority", "is_not", "manager")]),
  ],
  ["multiselect has_any_of", group([rule("tags", "has_any_of", ["travel"])])],
  [
    "multiselect has_all_of",
    group([rule("tags", "has_all_of", ["travel", "client"])]),
  ],
  ["multiselect has_none_of", group([rule("tags", "has_none_of", ["client"])])],
  ["multiselect empty", group([rule("tags", "empty")])],
  ["multiselect not_empty", group([rule("tags", "not_empty")])],
  ["boolean is", group([rule("billable", "is", true)])],
  ["boolean is_not", group([rule("billable", "is_not", true)])],
  ["boolean empty", group([rule("billable", "empty")])],
  ["relation is", group([rule("approver", "is", APPROVER)])],
  ["relation is_not", group([rule("approver", "is_not", APPROVER)])],
  ["relation not_empty", group([rule("approver", "not_empty")])],
  [
    "timestamptz is today",
    group([
      rule("submittedAt", "is", { relative: { unit: "day", offset: 0 } }),
    ]),
  ],
  [
    "timestamptz is_before",
    group([rule("submittedAt", "is_before", day("2026-10-13"))]),
  ],
  [
    "timestamptz is_after with a time",
    group([
      rule("submittedAt", "is_after", { date: "2026-10-13", time: "09:00" }),
    ]),
  ],
  [
    "timestamptz is_on_or_after",
    group([rule("submittedAt", "is_on_or_after", day("2026-10-13"))]),
  ],
  [
    "timestamptz between",
    group([
      rule("submittedAt", "between", [day("2026-10-01"), day("2026-10-12")]),
    ]),
  ],
  [
    "timestamptz not_between",
    group([
      rule("submittedAt", "not_between", [
        day("2026-10-01"),
        day("2026-10-12"),
      ]),
    ]),
  ],
  [
    "timestamptz is_not",
    group([rule("submittedAt", "is_not", day("2026-10-13"))]),
  ],
  ["date is", group([rule("dueOn", "is", day("2026-10-13"))])],
  [
    "date is_on_or_before next week",
    group([
      rule("dueOn", "is_on_or_before", {
        relative: { unit: "week", offset: 1 },
      }),
    ]),
  ],
  ["date is_after", group([rule("dueOn", "is_after", day("2026-10-13"))])],
  ["date empty", group([rule("dueOn", "empty")])],
  ["negated flag", group([rule("status", "is", "submitted", true)])],
  [
    "nested groups",
    group([
      rule("status", "is_not", "draft"),
      group(
        [
          rule("amount", "gt", 1000),
          rule("submitter.seniority", "is", "manager"),
        ],
        "or",
      ),
    ]),
  ],
  [
    "or at the root with an unknown",
    group([rule("billable", "is", true), rule("amount", "lt", 0)], "or"),
  ],
  [
    "unfinished and unknown rules",
    group([
      rule("title", ""),
      rule("nope", "is", "x"),
      rule("status", "is", "paid"),
    ]),
  ],
  ["an empty tree", group([])],
];

describe.skipIf(!live)("rules module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("evaluates every operator the same way as evaluateFilterQuery", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "automations"]);
      await s.service();
      await createAutomationsAdmin({ transport: sqlTransport(s.sql) })
        .syncFields(expenses)
        .orThrow();

      const fields = await s.value<object>(
        "better_supabase.rule_field_map('expense')",
      );

      for (const [name, conditions] of CASES) {
        for (const [index, subject] of subjects.entries()) {
          const sql = await s.value<object>(
            "better_supabase.rule_evaluate($1, $2, $3, $4, $5)",
            [conditions, subject, fields, timeZone, now.toString()],
          );

          const local = evaluateRule({ conditions }, subject, expenses.fields, {
            now,
            timeZone,
          });

          expect(sql, `${name} on subject ${String(index)}`).toEqual(local);
        }
      }
    } finally {
      await s.close();
    }
  });

  it("checks trees, versions rules and gates publishing", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "automations"]);
      const owner = await s.user("owner");
      const editor = await s.user("admin");
      const member = await s.user("member");
      const rival = await s.user("rival");
      const tenant = await s.organization(owner, { admin: editor, member });
      const other = await s.organization(rival);

      await s.service();
      await createAutomationsAdmin({ transport: sqlTransport(s.sql) })
        .syncFields(expenses)
        .orThrow();

      const rules = createAutomations({ transport: sqlTransport(s.sql) });
      const submitted = group([rule("status", "is", "submitted")]);

      await s.as(owner);
      expect(
        (
          await rules.upsert(tenant, {
            subjectType: "invoice",
            trigger: "x",
            name: "x",
            conditions: submitted,
          })
        ).error?.hint,
      ).toBe("RULE_SUBJECT_UNKNOWN");
      expect(
        (
          await rules.upsert(tenant, {
            subjectType: "expense",
            trigger: "expense.submitted",
            name: "Bad",
            conditions: group([rule("amount", "contains", "1")]),
          })
        ).error?.hint,
      ).toBe("RULE_OPERATOR_INVALID");
      expect(
        (
          await rules.upsert(tenant, {
            subjectType: "expense",
            trigger: "expense.submitted",
            name: "Bad",
            conditions: group([rule("amount", "between", [1])]),
          })
        ).error?.hint,
      ).toBe("RULE_VALUE_INVALID");
      expect(
        (
          await rules.upsert(tenant, {
            subjectType: "expense",
            trigger: "expense.submitted",
            name: "Bad",
            conditions: submitted,
            actions: [{ kind: "Not A Kind" }],
          })
        ).error?.hint,
      ).toBe("AUTOMATION_ACTIONS_INVALID");

      const large = await rules
        .upsert(tenant, {
          subjectType: "expense",
          trigger: "expense.submitted",
          name: "Large expenses",
          conditions: group([
            rule("status", "is", "submitted"),
            rule("amount", "gt", 1000),
          ]),
          actions: [
            { kind: "approvals.request", config: { action: "finance_review" } },
          ],
        })
        .orThrow();

      expect(large).toMatchObject({
        organizationId: tenant,
        enabled: false,
        version: 1,
        stopProcessing: false,
      });

      const all = await rules
        .upsert(tenant, {
          subjectType: "expense",
          trigger: "expense.submitted",
          name: "Every submitted expense",
          conditions: submitted,
          actions: [{ kind: "notifications.send" }],
          enabled: true,
        })
        .orThrow();

      expect(all.rank > large.rank).toBe(true);

      await s.as(editor);

      const renamed = await rules
        .upsert(tenant, { id: large.id, version: 1, name: "Large ones" })
        .orThrow();

      expect(renamed.version).toBe(2);
      expect(
        (
          await rules.upsert(tenant, {
            id: large.id,
            version: 1,
            name: "Stale",
          })
        ).error?.hint,
      ).toBe("AUTOMATION_CONFLICT");
      expect(
        (await rules.versions(large.id).orThrow()).map(
          (entry) => entry.version,
        ),
      ).toEqual([2, 1]);

      await s.as(member);
      const listed = await rules.list(tenant).orThrow();
      expect(
        listed.filter((r) => r.defaultKey === undefined).map((r) => r.id),
      ).toEqual([large.id, all.id]);
      expect(
        listed
          .flatMap((r) => (r.defaultKey === undefined ? [] : [r.defaultKey]))
          .toSorted(),
      ).toEqual([
        "hiring.application_to_employee",
        "inbox.conversation_to_task",
        "quotes.quote_to_order",
      ]);
      expect(
        (await rules.upsert(tenant, { id: large.id, name: "Mine" })).error
          ?.hint,
      ).toBe("AUTOMATION_FORBIDDEN");
      expect((await rules.setEnabled(large.id, true)).error?.hint).toBe(
        "AUTOMATION_FORBIDDEN",
      );

      await s.as(rival);
      expect(await rules.get(large.id).orThrow()).toBeUndefined();
      expect((await rules.list(tenant)).error?.hint).toBe(
        "AUTOMATION_FORBIDDEN",
      );
      expect(
        (await rules.list(other).orThrow()).filter(
          (r) => r.defaultKey === undefined,
        ),
      ).toEqual([]);

      await s.as(owner);

      const shipped = listed.find(
        (r) => r.defaultKey === "inbox.conversation_to_task",
      );

      if (shipped === undefined) {
        throw new Error("The inbox default automation wasn't installed");
      }

      expect((await rules.remove(shipped.id)).error?.hint).toBe(
        "AUTOMATION_DEFAULT",
      );
      await rules.upsert(tenant, { id: shipped.id, name: "Renamed" }).orThrow();
      expect((await rules.resetDefault(shipped.id).orThrow()).name).toBe(
        shipped.name,
      );
      expect((await rules.resetDefault(large.id)).error?.hint).toBe(
        "AUTOMATION_NOT_DEFAULT",
      );

      await rules.setEnabled(large.id, true).orThrow();
      await rules
        .upsert(tenant, { id: large.id, stopProcessing: true })
        .orThrow();

      const expense = subjects[0];

      const matches = await rules
        .matching(tenant, {
          subjectType: "expense",
          trigger: "expense.submitted",
          subject: expense,
        })
        .orThrow();

      expect(matches.map((match) => match.rule.id)).toEqual([large.id]);
      expect(
        (
          await rules
            .matching(tenant, {
              subjectType: "expense",
              trigger: "expense.submitted",
              subject: { ...expense, amount: 20 },
            })
            .orThrow()
        ).map((match) => match.rule.id),
      ).toEqual([all.id]);

      const tested = await rules.test(large, subjects[1]).orThrow();

      expect(tested.matched).toBe(false);
      expect(
        (await rules.evaluations(large.id).orThrow()).map(
          (entry) => entry.mode,
        ),
      ).toEqual(["test"]);

      await s.service();

      const run = await createAutomationsAdmin({
        transport: sqlTransport(s.sql),
      })
        .run(tenant, {
          subjectType: "expense",
          trigger: "expense.submitted",
          subjectId: "exp_1",
          subject: expense,
        })
        .orThrow();

      expect(run.map((match) => match.rule.id)).toEqual([large.id]);

      const requested: unknown[] = [];

      const dispatched = await createRuleDispatcher({
        actions: createActionRegistry([
          defineAction({
            kind: "approvals.request",
            title: "Request an approval",
            run: ({ action, context }) => {
              requested.push([action.config, context.subjectId]);

              return ok("requested");
            },
          }),
        ]),
      })
        .dispatch([...run, { rule: all, results: {} }], {
          organizationId: tenant,
          subjectType: "expense",
          subjectId: "exp_1",
        })
        .orThrow();

      expect(requested).toEqual([[{ action: "finance_review" }, "exp_1"]]);
      expect(dispatched.map((outcome) => outcome.ok)).toEqual([true, false]);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 order by created_at",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual(
        expect.arrayContaining(["rule.saved", "rule.enabled", "rule.matched"]),
      );

      await s.as(editor);
      expect(await rules.remove(all.id).orThrow()).toBe(true);
      await s.as(member);
      expect(await rules.remove(large.id).orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });
});
