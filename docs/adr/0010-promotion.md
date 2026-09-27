# 10. Promotion by pull request

Date: 2026-06-14

## Context

The digest in an environment's values is the only thing that decides what
runs there (ADR 3). Promotion is therefore a change to one line, and the
question is only who is allowed to make it and what has to pass first.

## Decision

Staging follows main. After every green build on main, the service's CI
opens a pull request here that sets the new digest in
`environments/staging`, and enables auto merge. It lands as soon as this
repo's checks pass.

Prod is promoted by hand. The `promote` workflow copies the digest that is
currently in staging into `environments/prod` and opens a pull request.
CODEOWNERS requires a review for anything under `environments/prod`,
`clusters/prod` and `platform/policies`. The pull request carries the digest
and the command to verify its signature.

Nothing skips staging: the workflow can only copy the digest currently
committed for staging, and there is no input for choosing a different one.
Whether staging is actually synced and healthy on it is for the reviewer to
check; the pull request says so.

Both kinds of pull request are opened with a GitHub App token, not with
`GITHUB_TOKEN`. Pull requests opened by `GITHUB_TOKEN` do not trigger
workflows, so the checks would never run on them.

Every pull request runs the same checks: every cluster and environment is
rendered, validated against the schemas and run through the admission
policies with the Kyverno CLI, and a parity check fails if an environment's
values set anything other than size, image digest or routing.

## Consequences

Promotion history is the git history of one file per environment, and a
rollback is a revert of one pull request. The cost is a GitHub App that has
write access to this repo, whose key lives in two repositories' secrets.
