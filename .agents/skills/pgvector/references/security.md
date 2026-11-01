# pgvector security

> Verified against pgvector v0.8.7 and Postgres Docker image docs (docker-library/postgres), 2026-10-11

pgvector adds no auth of its own; secure Postgres.

- **Bind narrowly.** Publish `127.0.0.1:5432:5432` or use a private Docker network. The official image listens on all container interfaces by default.
- **Passwords.** `POSTGRES_PASSWORD` in a `0600` env file; clients use `~/.pgpass` (`0600`) or `PGPASSFILE`. Avoid URLs with passwords in command lines and logs. Postgres 14+ defaults to SCRAM for new passwords; verify `password_encryption`.
- **Roles.** One role per app with only the needed grants; the app does not need superuser. Create the extension once as an admin (`CREATE EXTENSION vector;`), then grant `USAGE`/table access. Open WebUI can run as a non-superuser when `PGVECTOR_CREATE_EXTENSION=false` and the extension is pre-created.
- **TLS.** Enable `ssl = on` with certificates, require `sslmode=verify-full` clients, or terminate on a private network. Edit `pg_hba.conf` to `hostssl` for non-local clients.
- **Row-level security** applies to vector tables like any other; use it for tenant isolation, but remember similarity search metadata can leak through shared indexes only if RLS is not enforced.
- **Backups contain embeddings and chunk text**: protect dumps like the source documents.
- **Image provenance.** Pin tags, record digests.
