import { describe, expect, it } from "vitest";

import type { RunProcess } from "../../src/cli/exec.ts";

import { parseEnv } from "../../src/cli/env.ts";
import {
  parseIpcs,
  parseIpcsSizes,
  parsePs,
  readSharedMemory,
  stackIdOf,
} from "../../src/cli/shm.ts";

const MAC_IPCS = `IPC status from <running system> as of Wed Oct 21 10:00:00 CEST 2026
T     ID     KEY        MODE       OWNER    GROUP  SEGSZ  CPID  LPID
Shared Memory:
m  65536 0x0052e2c1 --rw------- martijn    staff     56  4242  4242
m  65537 0x0052e2c2 --rw------- martijn    staff 1048576  5151  5151
`;

const LINUX_PIDS = `
------ Shared Memory Creator/Last-op PIDs --------
shmid      owner      cpid       lpid
32768      dev        4242       4243
`;

const LINUX_SIZES = `
------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status
0x0052e2c1 32768      dev        600        56         6
`;

const POSTMASTER =
  "/Users/me/.supabase/cache/stack/bin/.postgres-wrapped -D /Users/me/.supabase/stacks/aed6a8a0a5c343ef9f88/data/1/data -c port=5432";

const env = parseEnv({});

function fake(outputs: Readonly<Record<string, string>>): RunProcess {
  return (command, args) =>
    Promise.resolve({
      code: 0,
      stderr: "",
      stdout: outputs[[command, ...args].join(" ")] ?? outputs[command] ?? "",
    });
}

describe("parseIpcs", () => {
  it("reads the id, size and creator PID on macOS", () => {
    expect(parseIpcs(MAC_IPCS)).toEqual([
      { id: "65536", pid: 4242, bytes: 56 },
      { id: "65537", pid: 5151, bytes: 1_048_576 },
    ]);
  });

  it("reads the id and creator PID without the size column", () => {
    expect(
      parseIpcs("m  65536 0x0052e2c1 --rw------- me staff  4242  4242"),
    ).toEqual([{ id: "65536", pid: 4242 }]);
  });

  it("reads the id and creator PID on Linux", () => {
    expect(parseIpcs(LINUX_PIDS)).toEqual([{ id: "32768", pid: 4242 }]);
  });

  it("reads the sizes on Linux", () => {
    expect(parseIpcsSizes(LINUX_SIZES)).toEqual(new Map([["32768", 56]]));
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
  it("ties each segment to the stack whose postmaster created it", async () => {
    const run = fake({
      ipcs: MAC_IPCS,
      sysctl: "32\n",
      ps: ` 4242 ${POSTMASTER}\n 5151 /usr/bin/other\n`,
    });

    expect(await readSharedMemory("/repo", env, run, "darwin")).toEqual({
      supported: true,
      limit: 32,
      segments: [
        { id: "65536", pid: 4242, bytes: 56, stackId: "aed6a8a0a5c343ef9f88" },
        { id: "65537", pid: 5151, bytes: 1_048_576 },
      ],
    });
  });

  it("joins the PIDs and sizes on Linux", async () => {
    const run = fake({
      "ipcs -m -p": LINUX_PIDS,
      "ipcs -m": LINUX_SIZES,
      cat: "4096\n",
      ps: ` 4242 ${POSTMASTER}\n`,
    });

    expect(await readSharedMemory("/repo", env, run, "linux")).toEqual({
      supported: true,
      limit: 4096,
      segments: [
        { id: "32768", pid: 4242, bytes: 56, stackId: "aed6a8a0a5c343ef9f88" },
      ],
    });
  });

  it("reports unsupported when ipcs can't run", async () => {
    const run: RunProcess = () =>
      Promise.resolve({ code: 127, stdout: "", stderr: "not found" });

    expect(await readSharedMemory("/repo", env, run, "darwin")).toEqual({
      supported: false,
      segments: [],
    });
    expect(await readSharedMemory("/repo", env, run, "linux")).toEqual({
      supported: false,
      segments: [],
    });
  });
});
