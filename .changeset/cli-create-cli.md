---
"better-supabase": minor
---

`better-supabase/cli` exports `createCli({ commands })` in place of `registerCommand`. It returns a CLI with your commands next to the built-in ones, so two CLIs in one process share no state. `defineCliCommand` now marks each command with `apiVersion: 1`, and `createCli` refuses a command without it or one that takes a built-in or reserved name (`login`, `logout`, `whoami`, `link`, `projects`, `deploy`, `cloud`).

The 0.2 command form, `(context) => CommandResult`, and the `Command`, `CommandContext` and `ParsedArgs` types are removed. Wrap such a command in `defineCliCommand`:

```ts
// Before
registerCommand("schemas", ({ args }) => ({
  code: 0,
  output: args.rest.join(" "),
}));

// After
const cli = createCli({
  commands: {
    schemas: defineCliCommand({
      meta: { name: "schemas" },
      args: {},
      run: async (args) => ({ code: 0, output: args._.join(" ") }),
    }),
  },
});
await cli.run(process.argv.slice(2), { cwd: process.cwd(), env: process.env });
```

`doctor --metadata` now reports a conflicting flag with the same message as `gen --metadata`, and `doctor` lists `--snapshot`, `--db-url-stdin` and `--project-ref` first in its help.
