# Install pgvector

> Verified against pgvector v0.8.7 (README Installation and Docker sections, Docker Hub pgvector/pgvector, docker-library/postgres docs), 2026-10-11

Latest tag at the check date: v0.8.7. Supports Postgres 13+.

## Docker (recommended beside an LLM stack)

Images `pgvector/pgvector:<tag>` add pgvector to the official Postgres image. Supported tags per the README: `pg18-trixie` and `0.8.7-pg18-trixie`, `pg18-bookworm` (also `pg18`), then the same patterns for `pg17`, `pg16`, `pg15`, `pg14`, `pg13` (trixie variants only exist for 13 to 18 as listed upstream; re-read the README list). Pin the full `0.8.7-pg18-trixie` style tag.

```bash
install -d -m 700 ~/pgvector && cd ~/pgvector
umask 077; printf 'POSTGRES_USER=app\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=rag\n' "$(openssl rand -hex 24)" > pg.env

docker run -d --name pgvector --env-file pg.env --shm-size=1g \
  -p 127.0.0.1:5432:5432 -v pgvector-data:/var/lib/postgresql \
  pgvector/pgvector:0.8.7-pg18-trixie
```

- **Postgres 18 changed `PGDATA`** to be version specific (`/var/lib/postgresql/18/docker`), so the volume mounts at `/var/lib/postgresql`. For 17 and older the data dir is `/var/lib/postgresql/data`. Mounting the wrong path loses data on container removal.
- `--shm-size=1g` is the README's note for parallel index builds (default 64 MB of `/dev/shm` breaks them).
- Create the extension per database: `CREATE EXTENSION vector;` (needs a superuser or a trusted-extension-capable role; the official image's `POSTGRES_USER` is a superuser). Auto-create with an init script mounted at `/docker-entrypoint-initdb.d/` (`templates/schema.sql`).
- Check: `psql "host=127.0.0.1 dbname=rag user=app" -c '\dx vector'`.

## Existing Postgres

- Linux/macOS from source (README): `git clone --branch v0.8.7 https://github.com/pgvector/pgvector.git && cd pgvector && make && make install`. Needs server dev headers and a compiler.
- Packaged: Homebrew, APT, Yum, PGXN, apk, conda-forge are listed upstream; most hosted Postgres providers ship it preinstalled.
- Run `CREATE EXTENSION vector;` once per database.

## Versions

Index and type availability depends on the pgvector version: iterative scans exist from 0.8.0; `halfvec`, `sparsevec` and binary quantization expressions are in 0.7.0 and later per the README sections. Check `select extversion from pg_extension where extname='vector';`.
