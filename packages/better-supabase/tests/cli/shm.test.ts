import { describe, expect, it } from "vitest";

import type { RunProcess } from "../../src/cli/exec.ts";

import { parseEnv } from "../../src/cli/env.ts";
import {
  parseIpcs,
  parsePs,
  readSharedMemory,
  stackIdOf,
} from "../../src/cli/shm.ts";

const MAC_IPCS = `IPC status from <running system> as of Wed Oct 21 10:00:00 CEST 2026
T     ID     KEY        MODE       OWNER    GROUP  CPID  LPID
Shared Memory:
m  65536 0x0052e2c1 --rw------- martijn    staff  4242  4242
m  65537 0x0052e2c2 --rw------- martijn    staff  5151  5151
`;

const LINUX_IPCS = `
------ Shared Memory Creator/Last-op PIDs --------
shmid      owner      cpid       lpid
32768      dev        4242       4243
`;

const POSTMASTER =
  "/Users/me/.supabase/cache/stack/bin/.postgres-wrapped -D /Users/me/.supabase/stacks/aed6a8a0a5c343ef9f88/data/1/data -c port=5432";

describe("parseIpcs", () => {
  it("reads the segment id and creator PID on macOS", () => {
    expect(parseIpcs(MAC_IPCS)).toEqual([
      { id: "65536", pid: 4242 },
      { id: "65537", pid: 5151 },
    ]);
  });

  it("reads the segment id and creator PID on Linux", () => {
    expect(parseIpcs(LINUX_IPCS)).toEqual([{ id: "32768", pid: 4242 }]);
  });
});

describe("stackIdOf", () => {
  it("finds the stack id in the postmaster's data directory", () => {
    expect(stackIdOf(POSTMASTER)).toBe("aed6a8a0a5c343ef9f88");
  });

  it("returns nothing for another process", () => {
    expect(stackIdOf("/usr/bin/some-app --flag")).toBeUndefined();
  });
});

describe("parsePs", () => {
  it("maps each PID to its command", () => {
    expect(parsePs(` 4242 ${POSTMASTER}\n 5151 /usr/bin/other\n`)).toEqual(
      new Map([
        [4242, POSTMASTER],
        [5151, "/usr/bin/other"],
      ]),
    );
  });
});

describe("readSharedMemory", () => {
  const env = parseEnv({});

  it("ties each segment to the stack whose postmaster created it", async () => {
    const run: RunProcess = (command) =>
      Promise.resolve({
        code: 0,
        stderr: "",
        stdout:
          command === "ipcs"
            ? MAC_IPCS
            : command === "sysctl" || command === "cat"
              ? "32\n"
              : ` 4242 ${POSTMASTER}\n 5151 /usr/bin/other\n`,
      });

    const usage = await readSharedMemory("/repo", env, run, "darwin");

    expect(usage.supported).toBe(true);
    expect(usage.segments).toEqual([
      { id: "65536", pid: 4242, stackId: "aed6a8a0a5c343ef9f88" },
      { id: "65537", pid: 5151 },
    ]);
    expect(usage.limit).toBe(32);
  });

  it("reports unsupported when ipcs can't run", async () => {
    const run: RunProcess = () =>
      Promise.resolve({ code: 127, stdout: "", stderr: "not found" });

    expect(await readSharedMemory("/repo", env, run)).toEqual({
      supported: false,
      segments: [],
    });
  });
});
