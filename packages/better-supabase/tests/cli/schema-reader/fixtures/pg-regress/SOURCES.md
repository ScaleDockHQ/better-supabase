# Postgres regression scripts

These files hold the statements of a few Postgres regression scripts that
parse on their own under Postgres 17. `corpus.test.ts` reads each one with the
schema reader, checks that the statement splitter finds as many statements as
the parser, and checks that the deparsed text parses back to the same tree.

`node scripts/curate-pg-regress.ts` downloads the scripts from libpg_query at
tag `17-6.1.0` (the tag `@supabase/pg-parser` 0.1.7 builds Postgres 17 from),
checks each SHA-256 below, drops psql commands and every statement that
doesn't parse alone (psql variables, statements meant to fail), and writes the
rest. Don't edit the files by hand; change the script and run it again.

Base URL:
`https://raw.githubusercontent.com/pganalyze/libpg_query/17-6.1.0/test/sql/postgres_regress/`

| File                      | SHA-256 of the source                                              |
| ------------------------- | ------------------------------------------------------------------ |
| `alter_table.sql`         | `35caa7a80fca260bdc004c1055e200ddee78fb8f0920ecfb3401a0d62400b947` |
| `create_function_sql.sql` | `f4208caa58b82a29768fa759f8959eb2bca000810e18a4886eabb80c79813683` |
| `create_index.sql`        | `d991e99d4b8e1d33c40d656f3eefb349e0bca49f378e8385eae5581ac9047400` |
| `create_schema.sql`       | `a33cdfc52a49c5bf3cf168e6cb927aae3557507ddd8a4077dff7c481c4254492` |
| `create_table.sql`        | `2b1e8bfdbe736ac40ebc995c8e2b31df7668dd2724f6ee438726a4fc0b43520f` |
| `create_type.sql`         | `09684b3556f74942c7694d42bc7c0755bfdbfa594feb0affb737d211c5ee826b` |
| `create_view.sql`         | `2f1353de99bb13ff7994f53c975936b82b20a2cd6212acbee4d51dfed5a42f08` |
| `rowsecurity.sql`         | `cea7b02384c11f303730447b38a39f3028a3e7b7153012b4689b44e8ada29fb1` |
| `triggers.sql`            | `bff8b57a574ee15c719ccd41ed1f6d49474bc245ff686832c22d4abe9b19a57c` |

## Licenses

The scripts come from the PostgreSQL source tree (`src/test/regress/sql`),
under the PostgreSQL License:

> Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
> Portions Copyright (c) 1994, The Regents of the University of California
>
> Permission to use, copy, modify, and distribute this software and its
> documentation for any purpose, without fee, and without a written agreement
> is hereby granted, provided that the above copyright notice and this
> paragraph and the following two paragraphs appear in all copies.
>
> IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
> DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING
> LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION,
> EVEN IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF
> SUCH DAMAGE.
>
> THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
> INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
> FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN
> "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATIONS TO
> PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

libpg_query, which copies them into `test/sql/postgres_regress`, is under the
BSD 3-Clause License (Copyright (c) 2015, Lukas Fittl; Copyright (c)
2016-2023, Duboce Labs, Inc. (pganalyze)).
