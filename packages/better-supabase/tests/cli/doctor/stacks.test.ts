import { beforeEach, describe, expect, it, vi } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type { SharedMemorySegment } from "../../../src/cli/shm.ts";

import {
  loadLocalStackCheck,
  STACK_RULES,
} from "../../../src/cli/doctor/stacks.ts";
import { readSharedMemory } from "../../../src/cli/shm.ts";
import { listStacks } from "../../../src/cli/stacks.ts";

vi.mock(import("../../../src/cli/shm.ts"), async (importOriginal) => ({
  ...(await importOriginal()),
  readSharedMemory: vi.fn<typeof readSharedMemory>(),
}));

vi.mock(import("../../../src/cli/stacks.ts"), async (importOriginal) => ({
  ...(await importOriginal()),
  listStacks: vi.fn<typeof listStacks>(),
}));

const STACK = {
  id: "aed6a8a0a5c343ef9f88",
  projectRoot: "/code/cloud",
  name: "cloud",
  branch: "refs/heads/feat/rebuild",
  runtime: "native",
  running: true,
};

function check(code: string, localStacks: DoctorContext["localStacks"]) {
  const rule = STACK_RULES.find((candidate) => candidate.code === code)!;

  // SAFETY: BS700 and BS701 read only localStacks from the context.
  return rule.check({ localStacks } as DoctorContext);
}

const interlocks = (count: number, stackId?: string): SharedMemorySegment[] =>
  Array.from({ length: count }, (_, index) => ({
    id: String(index),
    pid: index,
    bytes: 56,
    ...(stackId === undefined || index > 0 ? {} : { stackId }),
  }));

describe("BS700", () => {
  it("warns at 80% of the limit and names the stacks that hold segments", () => {
    expect(
      check("BS700", {
        memory: {
          supported: true,
          limit: 32,
          segments: interlocks(26, STACK.id),
        },
        stacks: [STACK],
      }),
    ).toEqual([
      {
        target: "kern.sysv.shmmni",
        message:
          "26 of 32 shared memory segments are in use, 1 of them by managed stacks: aed6a8a0a5c3 (feat/rebuild in /code/cloud). Run better-supabase stack prune --stop-idle to free them.",
      },
    ]);
  });

  it("stays quiet below the threshold, without a limit, or when skipped", () => {
    expect(
      check("BS700", {
        memory: { supported: true, limit: 32, segments: interlocks(25) },
        stacks: [],
      }),
    ).toEqual([]);
    expect(
      check("BS700", {
        memory: { supported: true, segments: interlocks(40) },
        stacks: [],
      }),
    ).toEqual([]);
    expect(check("BS700", { skipped: "ipcs is not available." })).toEqual([]);
  });

  it("leaves out the stacks when none of the segments belong to one", () => {
    expect(
      check("BS700", {
        memory: { supported: true, limit: 32, segments: interlocks(30) },
        stacks: [],
      }),
    ).toEqual([
      {
        target: "kern.sysv.shmmni",
        message:
          "30 of 32 shared memory segments are in use. Run better-supabase stack prune --stop-idle to free them.",
      },
    ]);
  });
});

describe("BS701", () => {
  it("flags a stack that keeps its shared buffers in System V memory", async () => {
    const [finding] = await check("BS701", {
      memory: {
        supported: true,
        limit: 32,
        segments: [
          { id: "1", pid: 1, bytes: 56, stackId: STACK.id },
          { id: "2", pid: 1, bytes: 150 * 1024 * 1024, stackId: STACK.id },
          { id: "3", pid: 2, bytes: 56, stackId: "other00000000" },
        ],
      },
      stacks: [STACK],
    });

    expect(finding?.target).toBe(STACK.id);
    expect(finding?.message).toContain(
      "holds 2 shared memory segment(s) (150 MB), so it sets shared_memory_type",
    );
  });

  it("accepts one interlock segment per stack", () => {
    expect(
      check("BS701", {
        memory: {
          supported: true,
          limit: 32,
          segments: interlocks(3, STACK.id),
        },
        stacks: [STACK],
      }),
    ).toEqual([]);
  });

  it("counts segments without a size and names a stack it can't find by id", () => {
    expect(
      check("BS701", {
        memory: {
          supported: true,
          limit: 32,
          segments: [
            { id: "1", pid: 1, stackId: "unknown00000000" },
            { id: "2", pid: 1, stackId: "unknown00000000" },
          ],
        },
        stacks: [],
      }),
    ).toEqual([
      {
        target: "unknown00000000",
        message: expect.stringContaining(
          "holds 2 shared memory segment(s), so it sets",
        ),
      },
    ]);
  });
});

describe("loadLocalStackCheck", () => {
  beforeEach(() => {
    vi.mocked(readSharedMemory).mockReset();
    vi.mocked(listStacks).mockReset().mockResolvedValue([STACK]);
  });

  it("skips when ipcs is not available", async () => {
    vi.mocked(readSharedMemory).mockResolvedValue({
      supported: false,
      segments: [],
    });

    expect(await loadLocalStackCheck("/code", {})).toEqual({
      skipped: "ipcs is not available.",
    });
  });

  it("reads the stacks only when a finding names them", async () => {
    const memory = { supported: true, limit: 32, segments: interlocks(2) };
    vi.mocked(readSharedMemory).mockResolvedValue(memory);

    expect(await loadLocalStackCheck("/code", {})).toEqual({
      memory,
      stacks: [],
    });
    expect(listStacks).not.toHaveBeenCalled();
  });

  it("reads the stacks near the limit and treats an unreadable list as empty", async () => {
    const memory = { supported: true, limit: 32, segments: interlocks(30) };
    vi.mocked(readSharedMemory).mockResolvedValue(memory);

    expect(await loadLocalStackCheck("/code", {})).toEqual({
      memory,
      stacks: [STACK],
    });

    vi.mocked(listStacks).mockRejectedValue(new Error("no stacks dir"));

    expect(await loadLocalStackCheck("/code", {})).toEqual({
      memory,
      stacks: [],
    });
  });

  it("reads the stacks when one holds a large segment", async () => {
    const memory = {
      supported: true,
      segments: [
        { id: "1", pid: 1, bytes: 4 * 1024 * 1024, stackId: STACK.id },
      ],
    };

    vi.mocked(readSharedMemory).mockResolvedValue(memory);

    expect(await loadLocalStackCheck("/code", {})).toEqual({
      memory,
      stacks: [STACK],
    });
  });

  it("skips with the reason when reading the segments fails", async () => {
    vi.mocked(readSharedMemory).mockRejectedValue(new Error("ipcs crashed"));

    expect(await loadLocalStackCheck("/code", {})).toEqual({
      skipped: "ipcs crashed",
    });
  });
});
