# 0633: Keep supports-color 11, ultracite 8.1.1 and Expo 58 together

- Status: accepted
- Date: 2026-11-10

## Context

The 68-package dependency bump made CI fail in three places, and the first fix rolled
supports-color back to 8.1.1, ultracite to 8.1.0 and expo-router, expo-server and Expo to 57. The
upgrades stay and the code changes instead.

## Decision

- supports-color 11 stays, and `overrides` still forces one copy. attw 0.18 depends on
  marked-terminal 7, which loads supports-hyperlinks 3. That package is CommonJS and calls the
  `supportsColor()` function of supports-color 7, which 11 does not export. marked-terminal 8
  (supports-hyperlinks 4) changes its export, which attw's `import TerminalRenderer from
  "marked-terminal"` does not accept. `supports-hyperlinks@3>supports-color` therefore keeps 7.2.0
  for that one consumer, and nothing else in the tree uses it. Drop the entry when attw moves to
  marked-terminal 8.
- ultracite 8.1.1 stays. Its `typescript/no-unsafe-enum-assignment` reported 12 findings in this
  tree. Three are real: commitlint's severities are `RuleConfigSeverity`, so the config now
  writes `RuleConfigSeverity.Error` and `.Disabled`. The other nine index a mapped type by a
  string key (`facets[key as F]`, `config.sorts[query.sort]`, `columns["tag"]`). No enum is
  involved in the types, so each carries a line comment with the reason and the count. A new
  finding of this shape needs the same comment, not a rule change.
- Expo moves to SDK 58 as one set: expo 58.0.23, expo-router 58.0.30, expo-server 58.0.6,
  expo-constants, expo-linking, `@expo/log-box`, `@expo/metro-runtime` and React Native 0.88.1.
  The tree holds one expo-server, so there is one `ImmutableRequest` type. The worklets override
  is removed, because expo-modules-core 58 accepts worklets 0.13. React Native 0.88 types
  `AppState.currentState` as `string | null | undefined`, so `AppStateLike.currentState` is now
  optional and nullable.
- PowerSync stays on `@powersync/common` 2.5.0. `syncWithAuth` takes the database as
  `SyncedDatabaseLike<NoInfer<C>>`, so the connector type comes from `options.connector` and not
  from the overloaded `connect`.

## Consequences

oxlint 1.93.0 and oxfmt 0.78.0 are newer than the catalog pins but were released less than
`minimumReleaseAge` before this change, so they stay on 1.92.0 and 0.74.0 until they age in.
