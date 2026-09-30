# 13. Terraform is applied by CI, prod after a review

Date: 2026-09-30

## Context

ADR 7 checks every Terraform change, but nothing said who applies it. Applying
from a laptop means credentials on laptops and state that nobody reviewed the
change to.

## Decision

The `infra` workflow plans both environments on every pull request that
touches `infra/aws` and writes the plans to the job summary. A merge to main
applies staging and then prod. The prod job runs in the `prod` GitHub
environment, which has required reviewers, so it waits for an approval after
staging has been applied.

Credentials come from GitHub OIDC. Each account has two roles, created by the
stack itself (`modules/github-deploy`):

- `plan`, assumable from pull requests of this repo only. ReadOnlyAccess, but
  no objects outside the state bucket and no secret values.
- `apply`, assumable only from a job in the GitHub environment of the same
  name. Administrator, because the stack creates IAM roles and KMS keys.

The state bucket and its KMS key come before the stack, so
`scripts/bootstrap-state.sh` creates them with the AWS CLI. After that, an
admin applies the stack once by hand to create the roles, and from then on
only CI applies.

## Consequences

No AWS keys live in the repository or on laptops after the first apply.
Staging always takes a change before prod does. The prod approval is given
against the pull request's plan and the staging result: the apply job plans
again after the approval and applies that plan, so drift in between shows up
in its summary but does not stop it.
