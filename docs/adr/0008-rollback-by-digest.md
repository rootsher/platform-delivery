# 8. Rollback is a digest revert

Date: 2026-01-18

## Context

Rolling back an application is easy until the release changed the schema. If
the old code cannot run against the new schema, a rollback needs a down
migration first, under pressure, in production.

## Decision

Migrations are written expand then contract. Release N may add columns or
tables, but release N-1 must keep working against the schema N left behind.
Removing things happens in a later release, once nothing uses them.

With that rule a rollback is a `git revert` of the digest change in this repo.
The migration stays applied and the old code ignores what it does not know.

Undoing the schema as well is a separate, deliberate runbook step: a Job from
the release N image runs `migrate down` (only that image contains the down
part of its own migration), and only then does the digest go back to N-1.

## Consequences

Some changes take two releases instead of one. In exchange the common case of
a rollback touches one line and no data.
