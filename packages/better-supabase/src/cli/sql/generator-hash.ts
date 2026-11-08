import { createHash } from "node:crypto";
import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";

const SOURCE = /\.(?:[cm]?[jt]s)$/u;

/**
 * Where the generator's code lives: `src/sql` when this runs from source, and
 * the folder of the bundled chunks otherwise.
 */
const generatorRoot = (): string => {
  const here = import.meta.dirname;

  return import.meta.url.endsWith(".ts") ? join(here, "../../sql") : here;
};

let held: Promise<string> | undefined;

async function walk(folder: string, found: string[]): Promise<void> {
  const entries = await readdir(folder, { withFileTypes: true }).catch(
    () => [],
  );

  await Promise.all(
    entries.map(async (entry) => {
      const path = join(folder, entry.name);

      if (entry.isDirectory()) {
        await walk(path, found);
      } else if (SOURCE.test(entry.name)) {
        const info = await stat(path);
        found.push(`${path}:${String(info.size)}:${String(info.mtimeMs)}`);
      }
    }),
  );
}

/**
 * A hash of the generator's files (path, size and modification time), so a dev
 * checkout or a rebuilt `dist` never serves output an older generator wrote.
 * Computed once per process.
 */
export function generatorHash(): Promise<string> {
  held ??= (async () => {
    const found: string[] = [];
    await walk(generatorRoot(), found);

    return createHash("sha256")
      .update(found.toSorted().join("\n"))
      .digest("hex");
  })();

  return held;
}
