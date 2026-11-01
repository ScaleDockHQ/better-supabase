# Updating and removing pgvector

> Verified against pgvector v0.8.7 (README Upgrading), 2026-10-11

```bash
psql "host=127.0.0.1 dbname=rag user=app" -Atc "select extversion from pg_extension where extname='vector'"
psql "host=127.0.0.1 dbname=rag user=app" -Atc "select default_version from pg_available_extensions where name='vector'"
```

## Back up

```bash
docker exec pgvector pg_dump -U app -Fc rag > ~/pgvector/rag-$(date +%F).dump
```

## Upgrade the extension

1. Dump first.
2. Replace the binaries (new image tag, or `make install` of the new tag).
3. In each database: `ALTER EXTENSION vector UPDATE;`.
4. Confirm `extversion`, run a known query and `EXPLAIN`.
5. Indexes are kept; the README lists per-version notes (for example index options added in 0.8.0 such as iterative scans). Reindex only if release notes say so.

## Upgrade Postgres major version

Use `pg_upgrade` or dump and restore into a new container; the target must have the same or newer pgvector installed. On Postgres 18 images the data path differs from older ones (see `install.md`), so do not mount an old volume layout onto 18.

## Teardown

```bash
docker rm -f pgvector                    # keeps the volume
# With explicit approval, after a verified dump:
# docker volume rm pgvector-data; rm ~/pgvector/pg.env
```

Remove app and Open WebUI settings that point at the database.
