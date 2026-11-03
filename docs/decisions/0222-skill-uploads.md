# 0222: Sync agent skills to provider skill stores

- Status: accepted
- Date: 2026-11-03

## Context

The AI SDK uploads skills with `uploadSkill` and refers to them by provider reference. Our agent skills had no files and no record of what a provider holds.

## Decision

- The `agents` module (version 2) adds `name`, `files`, `content_hash`, `latest_version` and `provider_refs` to `agent_skills`, and `record_skill_sync` for the service role.
- `syncSkill` hashes the files, skips the upload when the hash matches and records the reference. `anthropicSkillOptions`, `openaiShellSkills` and `harnessSkills` read the references.

## Consequences

A changed skill uploads once per provider. The files stay in ai-files, read through the app's `read` function.
