# xomtracks-infrastructure

> AWS infrastructure for Xomtracks.

## What This Is
Terraform IaC — DynamoDB `xomtracks-shares` (+ GSIs), Lambda, API Gateway,
EventBridge weekly cron, SSM, S3 + CloudFront for `xomtracks.xomware.com`.
See `docs/features/xomtracks/PLAN.md`.

## Stack
- Terraform, HCL, AWS

## Key Commands
```bash
terraform init
terraform plan
terraform apply
```

## Project Config
```yaml
pm_tool: github-projects
github_project_number: 2
github_project_owner: Xomware
base_branch: master
test_commands:
  - echo "no tests configured"
```

## Constraints
- Cognito: reuse the SHARED `xomware_users` pool via `data_cognito.tf` (SSM
  lookups), matching `meals-infrastructure`/`xomforms-infrastructure`'s
  pattern. Do NOT provision a new pool. New app client lives in
  `xomware-infrastructure` (the pool owner), not here.
- DynamoDB `xomtracks-shares`: GSI-1 `direction`/`messageDate` (MVP, time
  window per direction), GSI-2 `sharerHandle`/`messageDate` (reserved,
  fast-follow by-sharer view). Dedup on `messageGuid`+`sourceUrl`.
- No infrastructure changes / `terraform apply` without Dom's explicit
  approval — this repo is plan-only until that checkpoint.

## Lessons
