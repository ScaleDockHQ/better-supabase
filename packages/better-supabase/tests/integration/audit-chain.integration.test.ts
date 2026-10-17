import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createAuditChain,
  sqlTransport,
  type AuditCheckpointSigner,
} from "../../src/blocks/audit/index.ts";
import {
  createRetention,
  sqlTransport as lifecycleTransport,
} from "../../src/blocks/data-lifecycle/index.ts";
import { toBase64Url } from "../../src/core/base64.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const signer: AuditCheckpointSigner = {
  signJwt: (claims) =>
    AsyncResult.ok(
      `${toBase64Url(JSON.stringify({ alg: "EdDSA", kid: "k1" }))}.${toBase64Url(JSON.stringify(claims))}.sig`,
    ),
};

const chained = { modules: { audit: { options: { chain: true } } } };

describe.skipIf(!live)("audit hash chain", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("links each tenant's entries, finds an edited one and signs the heads", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["audit"], chained);
      const tenant = crypto.randomUUID();
      const ids: string[] = [];

      for (const name of ["deal.won", "deal.lost", "deal.reopened"]) {
        ids.push(
          await s.value<string>(
            "better_supabase.audit_event($1, tenant => $2)",
            [name, tenant],
          ),
        );
      }

      await s.service();
      await s.client.query("set local role service_role");

      const chain = createAuditChain({
        transport: sqlTransport(s.sql),
        signer,
        issuer: "https://app.example",
      });

      const verdict = await chain.verify({ organizationId: tenant }).orThrow();
      expect(verdict).toMatchObject({ valid: true, checked: 3, seq: 3 });

      const heads = await chain.heads().orThrow();
      expect(heads).toContainEqual({
        organizationId: tenant,
        seq: 3,
        hash: verdict.valid ? verdict.hash : "",
        entryId: ids[2],
      });
      const made = await chain.checkpoint().orThrow();
      expect(made.find((c) => c.organizationId === tenant)).toMatchObject({
        seq: 3,
        keyId: "k1",
        entryId: ids[2],
      });
      expect(
        (await chain.heads().orThrow()).some(
          (h) => h.organizationId === tenant,
        ),
      ).toBe(false);
      expect(
        await chain.checkpoints({ organizationId: tenant }).orThrow(),
      ).toHaveLength(1);
      expect(
        await s.hint(
          "select better_supabase.record_audit_checkpoint($1, 3, '00', 'k1', 'x')",
          [tenant],
        ),
      ).toBe("AUDIT_CHECKPOINT_MISMATCH");

      await s.client.query("reset role");
      await s.client.query("set local session_replication_role = replica");
      await s.client.query(
        "update better_supabase.audit_events set event_type = 'deal.forged' where id = $1",
        [ids[1]],
      );
      await s.client.query("set local session_replication_role = origin");
      await s.client.query("set local role service_role");
      expect(await chain.verify({ organizationId: tenant }).orThrow()).toEqual({
        valid: false,
        checked: 1,
        seq: 2,
        brokenAt: ids[1],
        reason: "hash",
      });
    } finally {
      await s.close();
    }
  });

  it("finds a deleted entry, a broken link and a truncated tail", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["audit"], chained);
      const tenant = crypto.randomUUID();
      const ids: string[] = [];

      for (const name of ["a.one", "a.two", "a.three", "a.four"]) {
        ids.push(
          await s.value<string>(
            "better_supabase.audit_event($1, tenant => $2)",
            [name, tenant],
          ),
        );
      }

      await s.service();
      await s.client.query("set local role service_role");

      const chain = createAuditChain({
        transport: sqlTransport(s.sql),
        signer,
        issuer: "https://app.example",
      });

      const verify = () => chain.verify({ organizationId: tenant }).orThrow();

      /** Runs `sql` past the append-only triggers, then undoes it after `check`. */
      const tampered = async (
        sql: string,
        id: string | undefined,
        check: () => Promise<void>,
      ) => {
        await s.client.query("savepoint tamper");
        await s.client.query("reset role");
        await s.client.query("set local session_replication_role = replica");
        await s.client.query(sql, [id]);
        await s.client.query("set local session_replication_role = origin");
        await s.client.query("set local role service_role");
        await check();
        await s.client.query("rollback to savepoint tamper");
      };

      await tampered(
        "delete from better_supabase.audit_events where id = $1",
        ids[1],
        async () => {
          expect(await verify()).toEqual({
            valid: false,
            checked: 1,
            seq: 3,
            brokenAt: ids[2],
            reason: "gap",
          });
        },
      );

      await tampered(
        "update better_supabase.audit_events set prev_hash = '\\x00' where id = $1",
        ids[2],
        async () => {
          expect(await verify()).toEqual({
            valid: false,
            checked: 2,
            seq: 3,
            brokenAt: ids[2],
            reason: "link",
          });
        },
      );

      await chain.checkpoint().orThrow();
      await tampered(
        "delete from better_supabase.audit_events where id = $1",
        ids[3],
        async () => {
          expect(await verify()).toEqual({
            valid: false,
            checked: 3,
            seq: 4,
            reason: "gap",
          });
        },
      );
      expect(await verify()).toMatchObject({ valid: true, checked: 4, seq: 4 });
    } finally {
      await s.close();
    }
  });

  it("drops whole expired months of a partitioned log unless a hold covers it", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(
        "drop table if exists better_supabase.audit_events cascade",
      );
      await s.install(["audit", "data-lifecycle"], {
        modules: {
          audit: {
            options: { chain: true, partitioned: true, restricted: true },
          },
        },
      });
      expect(
        await s.value<string>(
          "(select relkind::text from pg_class where oid = 'better_supabase.audit_events'::regclass)",
        ),
      ).toBe("p");
      expect(
        await s.value<number>(
          "(select count(*)::integer from pg_inherits where inhparent = 'better_supabase.audit_events'::regclass)",
        ),
      ).toBe(5);
      await s.client.query(
        "create table better_supabase.audit_events_p202301 partition of better_supabase.audit_events for values from ('2023-01-01 00:00Z') to ('2023-02-01 00:00Z')",
      );

      const [row] = await s.rows<{ id: string }>(
        "insert into better_supabase.audit_events (op, event_type, occurred_at) values ('event', 'system.old', '2023-01-15Z') returning id",
      );

      const old = row!.id;
      await s.client.query(
        "insert into better_supabase.audit_events_restricted (entry_id, metadata) values ($1, '{}')",
        [old],
      );
      await s.client.query("select better_supabase.audit_event('system.now')");

      await s.service();
      await s.client.query("set local role service_role");

      const retention = createRetention({
        transport: lifecycleTransport(s.sql),
      });

      const hold = await retention
        .placeHold({ reason: "Audit", kind: "audit" })
        .orThrow();

      const purge = "better_supabase.purge_audit_log(older_than => '1 year')";
      expect(await s.value<number>(purge)).toBe(0);
      expect(
        await s.value<string | null>(
          "to_regclass('better_supabase.audit_events_p202301')::text",
        ),
      ).not.toBeNull();

      await retention.releaseHold(hold.id).orThrow();
      expect(await s.value<number>(purge)).toBe(1);
      expect(
        await s.value<string | null>(
          "to_regclass('better_supabase.audit_events_p202301')::text",
        ),
      ).toBeNull();
      await s.client.query("reset role");
      expect(
        await s.value<number>(
          "(select count(*)::integer from better_supabase.audit_events_restricted)",
        ),
      ).toBe(0);
      await s.client.query("set local role service_role");
      expect(
        await s.value<number>("better_supabase.maintain_partitions()"),
      ).toBe(0);
      expect(
        await createAuditChain({ transport: sqlTransport(s.sql) })
          .verify()
          .orThrow(),
      ).toMatchObject({ valid: true, checked: 3 });
    } finally {
      await s.close();
    }
  });
});
