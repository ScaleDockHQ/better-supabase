# 0015: Extend blocks through fields, hooks and `extendBlock`

- Status: accepted
- Date: 2026-10-09

## Context

Blocks were configurable almost only on the SQL side: `sql.modules.<name>`
sets the mode, renames tables and columns, takes module options and calls
SQL `before_*` and `after_*` hooks. The TypeScript clients were closed:

- Extra columns were lost. Only `profiles` could add columns to a managed
  table, and it returned them as `Record<string, unknown>`. `organizations`
  wrote `options.attributes` but `mine()` dropped them.
- Block calls run through `BlockTransport` straight to SQL functions, so
  plugins, `validation()` and `sb.on("mutation")` never see them. The only
  way to steer a call in code was a callback that one block happened to
  offer (`canInvite`, `shouldDeliver`), and past that the app had to write
  SQL or switch the module to `mode: "custom"`.
- A block client had no `extend`, unlike repositories.

Every block call goes through `blockCall` and every block method returns an
`AsyncResult`, so a block client can be wrapped without changing the block.

## Decision

Blocks extend in four steps, from the least invasive to the most:

1. **Configure** with `sql.modules.<name>`, as before.
2. **Fields.** A module that supports extra columns declares the
   `extraColumns` option (column name to SQL type). `ModuleContext.extraColumns`
   in `src/sql/context.ts` validates it, rejects a column that shadows one of
   the table's mapped columns, and the module adds the columns to a managed
   table. Reads return them under their database names, built with
   `jsonb_build_object` rather than `to_jsonb(row)`, so a renamed column never
   leaks. The block creator takes `fields`, a Standard Schema per entity, that
   types the extra columns on writes and reads, validates writes into a
   `validation` `DbError`, and parses reads (`src/core/block-fields.ts`).
   Organizations, profiles and notifications (the `data` of each type) take it
   first.
3. **Hooks.** `withBlockHooks(client, hooks)` in `src/core/block-hooks.ts`
   wraps the methods of any block client. `before` may rewrite the arguments
   or refuse the call with a `DbError`; `after` receives a copy of the result
   and can't change it, as invariant 5 requires of observers. `createBlocks`
   takes `hooks` by block name, so every block gets them, and the pilot blocks
   also take `hooks` directly. For cross-cutting work (tracing, timeouts),
   `wrapTransport(transport, middleware)` takes a versioned
   `BlockTransportMiddleware` (`apiVersion: 1`) with a conformance kit.
4. **Extend.** `extendBlock(client, build)` adds methods built on the client
   and on `call`, a `BlockCall` in the module's schema with the block's error
   mappers. Redefining a base method throws, as it does for plugins: hooks
   change behaviour, `extendBlock` adds it.

`mode: "custom"` stays the last resort.

Mutating contract functions follow one hook naming convention:
`before_<entity>_<action>` and `after_<entity>_<action>`. A registry test
holds the pilot modules to it; the other modules follow in the rollout.

## Alternatives considered

- **Route block calls through the plugin pipeline.** Plugins work on the
  PostgREST IR (`transformQuery`, `beforeMutation` over table rows); block
  calls are SQL functions with arguments, so every hook would see an
  operation shape it can't read.
- **Derive block row types from the generated `Database` types.** It needs
  the app to generate types for the module schema, and the module's
  functions return stable keys rather than table rows. A Standard Schema
  types the same columns, validates them, and matches settings,
  notifications and jobs.
- **Return `to_jsonb(row)` from reads.** It returns every column under its
  database name, renamed ones included, and breaks the stable keys
  `adopt` mode depends on.
- **Let `after` hooks reshape results.** A hook that changes a result makes
  the block's documented return value a function of every hook installed.
  Reshaping belongs in `fields` (typed and validated) or in a new method
  added with `extendBlock`.

## Consequences

An app adds its own columns to a block and reads them back typed, refuses or
rewrites a call in code without writing SQL, and adds methods that call its
own SQL functions. Each block that takes `fields` needs its reads to return
the extra columns, so the rollout touches each module's read functions. Block
events stay a closed `BlockEventMap`: invariant 2 rules out `declare module`,
so app-defined block events need their own design and are a follow-up.
