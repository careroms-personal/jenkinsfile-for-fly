# Bootstrap

One-time, manual setup that creates the S3 bucket used as the state backend for `environments/uat`. Not part of the per-customer Jenkins Create/Delete pipelines — run this once, by hand, before `environments/uat` is used for the first time.

Uses a local backend for its own state (this directory's `terraform.tfstate`, not committed to git). It cannot use the S3 backend it's creating — that would be a chicken-and-egg problem.

## Run

```
tofu init
tofu apply -var="bucket_name=<globally-unique-bucket-name>"
```

Take the `bucket_name` output and put it into `environments/uat/backend.tf`.
