import { describe, expect, it, vi } from "vitest";

import { createCollaboration } from "../../src/blocks/collaboration/index.ts";
import { createScheduling } from "../../src/blocks/scheduling/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";

const done = <T>(data: T): AsyncResult<T> =>
  new AsyncResult(Promise.resolve(ok(data)));

const failure = (): AsyncResult<never> =>
  new AsyncResult<never>(Promise.resolve(err(dbError("not_found", "no"))));

// SAFETY: the helpers read only the methods the fakes define.
const parts = <T>(value: object): T => value as T;

describe("collaboration.discuss", () => {
  const subject = { type: "deal", id: "d1" };

  it("posts the comment, then attaches each tag", async () => {
    const attach = vi.fn(() => done(true));
    const create = vi.fn(() => done({ id: "c1" }));

    const collaboration = createCollaboration(
      parts({ parts: { comments: { create }, tags: { attach } } }),
    );

    const result = await collaboration.discuss({
      subject,
      comment: { body: "Hi" },
      tagIds: ["t1", "t2"],
    });

    expect(result.ok).toBe(true);
    expect(result.data).toEqual({ comment: { id: "c1" }, tagged: 2 });
    expect(attach).toHaveBeenCalledTimes(2);
  });

  it("returns the first failed attach and leaves the comment posted", async () => {
    const attach = vi.fn(() => failure());
    const create = vi.fn(() => done({ id: "c1" }));

    const collaboration = createCollaboration(
      parts({ parts: { comments: { create }, tags: { attach } } }),
    );

    const result = await collaboration.discuss({
      subject,
      comment: { body: "Hi" },
      tagIds: ["t1", "t2"],
    });

    expect(result.ok).toBe(false);
    expect(create).toHaveBeenCalledOnce();
    expect(attach).toHaveBeenCalledOnce();
  });
});

describe("scheduling.bookWithReminder", () => {
  const slot = {
    serviceId: "s1",
    resourceId: "r1",
    startsAt: Temporal.Instant.from("2026-12-01T09:00:00Z"),
    reminder: 60,
  };

  it("confirms the booking, then sets the reminder on it", async () => {
    const hold = vi.fn(() => done({ id: "b1" }));
    const upsert = vi.fn(() => done({ id: "rem1" }));

    const scheduling = createScheduling(
      parts({ parts: { bookings: { hold }, reminders: { upsert } } }),
    );

    const result = await scheduling.bookWithReminder(slot);

    expect(result.data).toEqual({
      booking: { id: "b1" },
      reminder: { id: "rem1" },
    });
    expect(hold).toHaveBeenCalledWith(
      expect.objectContaining({ serviceId: "s1", confirm: true }),
    );
    expect(upsert).toHaveBeenCalledWith({
      subject: { type: "booking", id: "b1" },
      when: 60,
    });
  });

  it("returns the reminder error and keeps the booking", async () => {
    const hold = vi.fn(() => done({ id: "b1" }));
    const upsert = vi.fn(() => failure());

    const scheduling = createScheduling(
      parts({ parts: { bookings: { hold }, reminders: { upsert } } }),
    );

    expect((await scheduling.bookWithReminder(slot)).ok).toBe(false);
    expect(hold).toHaveBeenCalledOnce();
  });

  it("stops when the slot cannot be booked", async () => {
    const upsert = vi.fn(() => done({ id: "rem1" }));

    const scheduling = createScheduling(
      parts({
        parts: { bookings: { hold: () => failure() }, reminders: { upsert } },
      }),
    );

    expect((await scheduling.bookWithReminder(slot)).ok).toBe(false);
    expect(upsert).not.toHaveBeenCalled();
  });
});
