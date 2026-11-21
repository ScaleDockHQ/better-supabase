import type pg from "pg";

import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { StreamEvent } from "./client.ts";
import type { EveServer, ServerOptions } from "./server.ts";

import { Client } from "./client.ts";
import { connect, eventually, runsOf, unique } from "./db.ts";
import { startServer } from "./server.ts";

const types = (events: readonly StreamEvent[]): string[] =>
  events.map((event) => event.type);

const count = (events: readonly StreamEvent[], type: string): number =>
  events.filter((event) => event.type === type).length;

/**
 * The scenarios every delivery mode has to pass, against one running eve
 * server.
 */
export function defineScenarios(label: string, options: ServerOptions): void {
  describe(label, () => {
    let server: EveServer;
    let client: Client;
    let pool: pg.Pool;

    beforeAll(async () => {
      pool = connect();
      server = await startServer(options);
      client = new Client(server.url);
    });

    afterAll(async () => {
      await server.stop();
      await pool.end();
    });

    it("starts a session and settles the first turn", async () => {
      const title = unique("hello");
      const id = await client.create(title);
      const events = await client.waitFor(id, "turn.settled");

      expect(types(events)).toContain("session.started");
      expect(count(events, "turn.started")).toBe(1);
      expect((await runsOf(pool, id, title)).length).toBeGreaterThan(0);
    });

    it("runs a tool call without executing the turn twice", async () => {
      const title = unique("tool:echo");
      const id = await client.create(title);
      const events = await client.waitFor(id, "turn.settled");

      expect(count(events, "call.settled")).toBe(1);
      expect(
        JSON.stringify(
          events.find((event) => event.type === "call.settled")?.data,
        ),
      ).toContain("ping");
      expect(count(events, "turn.started")).toBe(1);
      expect(count(events, "turn.settled")).toBe(1);

      const steps = await pool.query<{ step_name: string; attempt: number }>(
        "select step_name, attempt from workflow.workflow_steps where run_id = any($1)",
        [(await runsOf(pool, id, title)).map((run) => run.id)],
      );

      expect(steps.rows.length).toBeGreaterThan(0);
      expect(steps.rows.every((row) => row.attempt === 1)).toBe(true);
    });

    it("parks on an approval and resumes with the answer", async () => {
      const id = await client.create(unique("tool:delete_record"));
      const parked = await client.waitFor(id, "turn.paused");
      const opened = parked.find(
        (event) => event.type === "interaction.opened",
      );

      expect(opened?.data["request"]?.kind).toBe("approval");
      expect(types(parked)).not.toContain("turn.settled");

      const answer = await client.post(id, {
        answers: [
          { interactionId: opened?.data["interactionId"], optionId: "approve" },
        ],
      });

      expect(answer.status).toBeLessThan(300);

      const resumed = await client.waitFor(
        id,
        "turn.settled",
        parked.at(-1)?.line ?? 0,
      );
      expect(types(resumed)).toContain("interaction.settled");
      expect(JSON.stringify(resumed)).toContain("rec_1");
    });

    it("ends a session on request", async () => {
      const id = await client.create(unique("hello"));
      await client.waitFor(id, "turn.settled");
      await client.post(id, {}, "/end");
      const events = await client.waitFor(id, "session.ended");

      expect(events.at(-1)?.data["outcome"]).toBe("completed");
    });

    it("queues input behind a running turn when asked to", async () => {
      const id = await client.create(unique("slow words:3"));
      await client.waitFor(id, "turn.started");
      await client.send(id, "words:1", "queue");

      let seen = 0;
      const { events } = await client.follow(
        id,
        (event) => {
          if (event.type === "turn.settled") {
            seen += 1;
          }

          return seen === 2;
        },
        0,
        20_000,
      );
      const settled = count(events, "turn.settled");

      expect(settled).toBe(2);
      expect(JSON.stringify(events)).not.toContain("interrupted");
    });

    it("lets a steering message interrupt the running turn", async () => {
      const id = await client.create(unique("slow words:6"));
      await client.waitFor(id, "model.started");
      await client.send(id, "words:1");
      let consumed = false;

      const { events } = await client.follow(
        id,
        (event) => {
          consumed ||=
            event.type === "delivery.consumed" &&
            JSON.stringify(event.data).includes("words:1");

          return consumed && event.type === "turn.settled";
        },
        0,
        20_000,
      );

      expect(consumed).toBe(true);
      expect(count(events, "turn.started")).toBeLessThanOrEqual(2);
    });

    it("replays the stream from any stored index", async () => {
      const id = await client.create(unique("tool:echo"));
      await client.waitFor(id, "turn.settled");

      const full = await client.history(id);
      expect(full.tailIndex).toBeGreaterThan(0);

      const from = Math.floor((full.tailIndex ?? 0) / 2);
      const rest = await client.history(id, from);

      expect(rest.events.map((event) => event.line)).toEqual(
        full.events
          .filter((event) => event.line >= from)
          .map((event) => event.line),
      );
      expect(types(rest.events)).toEqual(
        types(full.events.filter((event) => event.line >= from)),
      );
    });

    // Last: the old run of a handoff stays active and its messages keep coming back, which would
    // slow the scenarios after it in a delivery mode that dispatches in batches.
    it("compacts, hands the session to a successor run and keeps answering", async () => {
      const title = unique("hello");
      const id = await client.create(title);
      await client.waitFor(id, "turn.settled");

      const compact = await client.post(id, {}, "/compact");
      expect(compact.status).toBeLessThan(300);
      await client.waitFor(id, "context.settled");

      const runs = await eventually(async () => {
        const found = await runsOf(pool, id, title);

        return found.length >= 2 ? found : undefined;
      });

      expect(runs.length).toBeGreaterThanOrEqual(2);

      const retained = await pool.query<{ n: string }>(
        "select count(*) as n from workflow.workflow_hooks where run_id = any($1) and token_retention_until is not null",
        [runs.map((run) => run.id)],
      );

      expect(Number(retained.rows[0]?.n)).toBeGreaterThan(0);

      const before = (await client.history(id)).tailIndex ?? 0;
      await client.send(id, "words:2");
      const events = await client.waitFor(id, "turn.settled", before);
      expect(count(events, "turn.settled")).toBeGreaterThanOrEqual(1);
    });
  });
}
