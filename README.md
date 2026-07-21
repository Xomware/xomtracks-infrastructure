# xomtracks-infrastructure

Terraform IaC for **Xomtracks** — DynamoDB `xomtracks-shares` (+ GSIs), API
Gateway, Lambdas, EventBridge cron, SSM secrets, S3 + CloudFront for
`xomtracks.xomware.com`.

See `docs/features/xomtracks/PLAN.md` in the local working tree for the full
spec.

## Setup

```bash
terraform init
terraform plan
```
