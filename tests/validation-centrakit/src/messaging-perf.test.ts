import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

interface PlanNode {
  "Node Type": string;
  "Relation Name"?: string;
  Alias?: string;
  "Actual Loops"?: number;
  "Actual Rows"?: number;
  "Rows Removed by Filter"?: number;
  Plans?: readonly PlanNode[];
}

interface ExplainRow {
  "QUERY PLAN": readonly { Plan: PlanNode; "Execution Time": number }[];
}

const flatten = (node: PlanNode): PlanNode[] => [
  node,
  ...(node.Plans ?? []).flatMap(flatten),
];

// The old policy sent every file_node conversation of every tenant through
// can_subject. The new policy keeps the same decision, but first prunes rows
// whose subject is not visible, so a foreign tenant costs one hashed set scan
// instead of one can_subject call per row.
describe.skipIf(!live)("conversation read performance", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("prunes foreign file_node conversations once per statement", async () => {
    await withCentraKit(pool, async (s) => {
      await s.as("service");

      const makeOrganization = async (
        name: string,
        user: string,
        role: string,
      ) => {
        const [{ id }] = (await s.rows<{ id: string }>(
          "insert into centrakit.organizations (name, slug) values ($1, $2) returning id",
          [name, `${name.toLowerCase()}-${crypto.randomUUID().slice(0, 8)}`],
        )) as [{ id: string }];

        await s.client.query(
          `insert into centrakit.organization_users (organization_id, user_id, role_id)
           values ($1, $2, $3)`,
          [id, user, role],
        );

        return id;
      };

      const seed = async (
        organization: string,
        user: string,
        count: number,
      ) => {
        const nodes = await s.rows<{ id: string }>(
          `insert into centrakit.file_node (organization_id, kind, name, created_by)
           select $1, 'file', 'file-' || g, $2 from generate_series(1, $3) g
           returning id`,
          [organization, user, count],
        );

        const conversations = await s.rows<{ id: string }>(
          `with conversation as (
             insert into better_supabase.conversations (tenant_id, kind, access, subject_type, subject_id)
             select $1, 'subject', 'subject', 'file_node', n.id::text from unnest($2::uuid[]) n(id)
             returning id
           )
           insert into better_supabase.messages (tenant_id, conversation_id, body, author_id, sent_at)
           select $1, c.id, 'hello', $3, now() from conversation c
           returning conversation_id as id`,
          [organization, nodes.map((node) => node.id), user],
        );

        return { nodes, conversations };
      };

      const orgA = await makeOrganization("Acme", USERS.owner, ROLES.owner);
      const orgB = await makeOrganization("Beta", USERS.admin, ROLES.admin);

      const own = await seed(orgA, USERS.owner, 1);
      const foreign = await seed(orgB, USERS.admin, 200);

      // Without statistics the planner picks a nested loop over the subject
      // set and the count takes seconds, as it would on a cold hosted table.
      await s.client.query(
        "analyze better_supabase.conversations, better_supabase.messages, centrakit.file_node",
      );

      await s.as("owner");
      await s.client.query("set local role authenticated");

      const measure = async (
        label: string,
        sql: string,
        params: readonly unknown[] = [],
      ) => {
        await s.rows(sql, params);
        const started = performance.now();
        const rows = await s.rows(sql, params);
        const ms = performance.now() - started;

        console.info(`${label}: ${ms.toFixed(1)} ms`);

        return { ms, rows };
      };

      // The hot paths an inbox and a comment thread call.
      const list = await measure(
        "list_comments foreign",
        "select better_supabase.list_comments($1, 'file_node', $2) as value",
        [orgB, foreign.nodes[0]!.id],
      );

      expect(list.ms).toBeLessThan(300);

      const counts = await measure(
        "comment_counts foreign 200",
        "select better_supabase.comment_counts($1, 'file_node', $2::text[]) as value",
        [orgB, foreign.nodes.map((node) => node.id)],
      );

      expect(counts.ms).toBeLessThan(300);

      // What the old policy paid: one can_subject call per foreign row.
      const perRow = await measure(
        "can_subject per foreign row",
        "select count(*) from unnest($1::text[]) id where better_supabase.can_subject('file_node', id, 'read')",
        [foreign.nodes.map((node) => node.id)],
      );

      console.info(`per-row can_subject total: ${perRow.ms.toFixed(1)} ms`);

      // The provider's row scope on its own, so a slow scope shows up here
      // instead of hiding behind the conversation policy.
      const scope = await measure(
        "authz_file_node_rows one foreign id",
        "select centrakit.authz_file_node_rows('fileNode.read', array[$1]::text[]) as value",
        [foreign.nodes[0]!.id],
      );

      expect(scope.ms).toBeLessThan(300);

      const [explain] = await s.rows<ExplainRow>(
        "explain (analyze, format json) select count(*) from better_supabase.conversations",
      );

      const query = explain!["QUERY PLAN"][0]!;
      const nodes = flatten(query.Plan);

      console.info(`count execution: ${query["Execution Time"].toFixed(1)} ms`);
      expect(query["Execution Time"]).toBeLessThan(300);

      const conversations = nodes.find(
        (node) =>
          node["Node Type"] === "Seq Scan" &&
          node["Relation Name"] === "conversations",
      );

      expect(conversations?.["Actual Rows"]).toBe(1);
      expect(conversations?.["Rows Removed by Filter"]).toBe(200);

      // The set check runs once, not once per row.
      const subjectSet = nodes.find(
        (node) =>
          node["Node Type"] === "Seq Scan" &&
          node["Relation Name"] === "file_node" &&
          node.Alias === "s",
      );

      expect(subjectSet?.["Actual Loops"]).toBe(1);
      expect(subjectSet?.["Rows Removed by Filter"]).toBe(200);

      // Prove the pruned rows never reach can_subject: replace it with a
      // function that raises, drop the one own-tenant conversation so no row
      // can pass the tenant branch, and count. A per-row call would raise.
      await s.client.query("reset role");
      await s.client.query(
        "delete from better_supabase.conversations where id = $1",
        [own.conversations[0]!.id],
      );
      await s.client.query(
        `create or replace function "better_supabase"."can_subject"(subject_type text, subject_id text, action text)
         returns boolean
         language plpgsql
         stable
         security invoker
         cost 1000
         set search_path = ''
         as $$
         begin
           raise exception 'can_subject ran for a pruned row: %', subject_id;
         end $$`,
      );
      await s.client.query("set local role authenticated");

      const rows = await s.rows<{ count: string }>(
        "select count(*) from better_supabase.conversations",
      );

      expect(rows[0]?.count).toBe("0");

      await s.client.query("reset role");
    });
  }, 600_000);
});
