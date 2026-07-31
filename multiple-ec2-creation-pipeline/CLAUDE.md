# OpenTofu Module: UAT EC2 Self-Portal

## Context

Jenkins-based self-service portal for provisioning EC2 instances. This spec covers **OpenTofu only** — Ansible-based configuration (Docker, nginx container) is a separate, later phase and is out of scope here.

## Business Requirement

- One EC2 instance per **UAT environment per customer**.
- Each customer's UAT may need a **different instance type / AMI**, since customers have their own setup processes.
- Every customer's infrastructure must be **fully isolated** — one OpenTofu state per customer, never a single state managing multiple EC2 instances.
- Jenkins (running as agents in Kubernetes) is the caller — this module will be invoked from a Jenkins pipeline, not run interactively.

## Non-Goals (this phase)

- No Ansible / Docker / nginx provisioning yet — instance-level OS configuration is future work.
- No VPC/subnet/security-group *creation* — an existing VPC/subnet will be reused (see Inputs below). Do not build networking from scratch.
- No multi-region support — single region (`ap-southeast-1`) for now. **Correction:** earlier drafts of this spec assumed `ap-southeast-7`; confirmed via testing that the existing VPC/subnet/security-group/S3 bucket all actually live in `ap-southeast-1`. Use `ap-southeast-1` everywhere — provider block, backend config, and any region references.

## Module Structure

```
opentofu/
├── modules/
│   └── uat-ec2/              # reusable module — shape of "one customer's UAT EC2"
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/
    └── uat/                  # caller config — what Jenkins actually invokes
        ├── customers/          # one YAML file per customer — see "Per-Customer Config" below
        │   ├── hello-world.yaml
        │   └── <customer>.yaml
        ├── main.tf            (calls module "uat-ec2", reads customers/${var.customer_name}.yaml)
        ├── variables.tf        (customer_name only — see Caller Config below)
        ├── backend.tf          (partial S3 backend config — key injected at init time)
        └── versions.tf
```

### Design rules

1. **`modules/uat-ec2` has no backend block.** Modules never define backends — only root/caller configs do.
2. **`environments/uat/backend.tf` uses a partial backend configuration.** Do not hardcode the state `key`. It must be supplied at `tofu init` time via `-backend-config`, e.g.:
   ```
   tofu init -input=false -reconfigure \
     -backend-config="key=uat/${CUSTOMER_NAME}/terraform.tfstate"
   ```
   Confirmed working exactly in this form during testing. `-input=false` matters in the Jenkins pipeline specifically — without it, a missing required backend value causes OpenTofu to hang on an interactive prompt rather than fail cleanly, which would hang a non-interactive CI agent indefinitely.
   This is how one-state-per-customer isolation is enforced — there is exactly one caller config, invoked N times with N different state keys, never N copies of the directory.
3. **State backend:** S3, with OpenTofu 1.8+ native locking (`use_lockfile = true`) — no DynamoDB table required.
4. **`environments/uat` is a thin caller.** One `module "this" { source = "../../modules/uat-ec2" ... }` block. `customer_name` comes from Jenkins via `-var`; everything else comes from that customer's YAML file (see "Per-Customer Config" below). No business logic lives here beyond wiring.

## Module Interface (`modules/uat-ec2`)

### Inputs (`variables.tf`)

| Variable | Type | Required | Notes |
|---|---|---|---|
| `customer_name` | string | yes | Identifier used for naming, tags, and (at the caller level) the state key. Must validate against `^[a-z0-9-]+$` (lowercase alphanumeric + hyphens only) — this value flows into the AWS resource `Name` tag and the S3 state path. Confirmed working via `tofu apply` test. |
| `instance_type` | string | yes | e.g. `t4g.micro`. Varies per customer's setup process. No default — must be explicit. Confirmed working via `tofu apply` test. |
| `subnet_id` | string | no | ID of an **existing, private** subnet the instance launches into: `subnet-05de5976e810ae03a` (VPC `vpc-09aa10f3b94994be4`, region `ap-southeast-1`). PoC decision: hardcoded as the variable's `default` in `modules/uat-ec2/variables.tf` rather than passed from the caller — same subnet is reused for every customer's UAT for now. To promote this to a real per-caller input later, just remove the `default`; no other refactor needed. No public IP is assigned (private subnet) — see Outputs note below. **Confirmed working.** |
| `vpc_security_group_ids` | list(string) | no | PoC decision, same pattern as `subnet_id`: hardcoded default `["sg-02b05989e0e617e14"]` inside the module. Resolved and confirmed working via `tofu apply` test — this was previously an open question, now closed. |

> **`ami_id` is NOT a module variable.** During implementation this became an `aws_ami` data source lookup (`data "aws_ami" "ubuntu"` — auto-resolves the latest matching Ubuntu AMI in-region) rather than a required input. This diverges from the original "customers may need different AMIs" business requirement — it's a deliberate PoC simplification, not an oversight. If/when customers genuinely need different AMIs, promote this to a variable with the data source as its `default` fallback (same pattern used for `subnet_id`/`vpc_security_group_ids`). Do not silently reintroduce `ami_id` as a required variable without also updating the per-customer YAML config (see below), since that's now the intended place for customer-specific overrides.

> Keep the input surface minimal beyond this. Do not add further speculative variables (key_pair_name, volume_size, etc.) until there's a real requirement — bake sensible fixed defaults into the module internals instead, and promote them to variables only when a customer actually needs to override.

> Note on `vpc_id`: not taken as a direct module input — a subnet is always scoped to exactly one VPC, so `subnet_id` alone is sufficient for `aws_instance` placement. If a security group needs to be looked up/created later, derive `vpc_id` from the subnet via a `data "aws_subnet"` lookup inside the module rather than adding a redundant `vpc_id` variable.

### Resources (`main.tf`)

- One `aws_instance` resource per module call.
- **Tagging contract — mandatory, do not change without updating the Jenkins List/Delete jobs that depend on it:**
  ```hcl
  tags = {
    Name        = "uat-${var.customer_name}"
    ManagedBy   = "jenkins-ec2-portal"
    Customer    = var.customer_name
    Environment = "UAT"
  }
  ```
  These tags are the mechanism the Jenkins "list EC2s created by this portal" job uses (`aws ec2 describe-instances --filters Name=tag:ManagedBy,Values=jenkins-ec2-portal`). Any resource created by this module must carry them.

### Outputs (`outputs.tf`)

| Output | Value |
|---|---|
| `instance_id` | `aws_instance.uat.id` |
| `private_ip` | `aws_instance.uat.private_ip` |

Confirmed: the target subnet (`subnet-05de5976e810ae03a`) is **private** — no public IP is assigned, so `public_ip` would always be null/empty and is not useful. Use `private_ip` instead. This is also the correct value for the future Ansible phase, since Jenkins (k8s) and all EC2 instances will share the same subnet/VPC, making the private IP directly reachable — no bastion/VPN needed.

These outputs will be consumed later by the Ansible phase (dynamic inventory) and by Jenkins for build result display — implement now even though the consumer doesn't exist yet.

## Caller Config (`environments/uat`)

- `variables.tf`: **only `customer_name`** is exposed as a caller-level variable now (validated `^[a-z0-9-]+$`). This is the single value Jenkins passes in via `-var="customer_name=${params.CUSTOMER_NAME}"`.
- `main.tf`: reads `customers/${var.customer_name}.yaml` via `yamldecode(file(...))`, then passes the decoded values (`instance_type`, and any future per-customer overrides) into the `module "this" { source = "../../modules/uat-ec2" ... }` block. See "Per-Customer Config" below for the full pattern.
- `backend.tf`: partial S3 backend (bucket + region only; `key` supplied at init time by the caller/Jenkins). **Bucket already exists — `degito-opentofu-state`, region `ap-southeast-1`.** No bootstrap creation needed; see updated S3 section below.
- `versions.tf`: pin OpenTofu and AWS provider versions (use current stable AWS provider; do not pin to an old major version without checking).

### Per-Customer Config: one YAML file per customer, not a shared file

**Decision:** each customer gets its own file at `environments/uat/customers/<customer_name>.yaml`, not one shared file listing all customers. Reasons:
- Matches the existing one-state-file-per-customer isolation model — inconsistent to isolate state but not config.
- No merge/concurrency risk if two Jenkins builds run for different customers simultaneously (separate files = zero contention).
- Blast radius stays small — a YAML error in one customer's file can't break another customer's plan/apply.
- Maps 1:1 onto what Jenkins already does: Create job takes `CUSTOMER_NAME` as its only real parameter, and `main.tf` does a direct filename lookup — no filtering/indexing logic needed.

**Example — `customers/hello-world.yaml`:**
```yaml
customer_name: hello-world
instance_type: t4g.micro
# ami_id: ami-xxxxx   # optional future override — see ami_id note in Module Interface above
```

**Usage in `main.tf`:**
```hcl
locals {
  customer_config = yamldecode(file("${path.module}/customers/${var.customer_name}.yaml"))
}

module "this" {
  source        = "../../modules/uat-ec2"
  customer_name = local.customer_config.customer_name
  instance_type = local.customer_config.instance_type
}
```

This means Jenkins's Create job only needs to supply **one** build parameter (`CUSTOMER_NAME`) — everything else about that customer's setup lives in version-controlled YAML, directly matching the original business rule ("customers have their own setup process"). Adding a new customer = adding a new YAML file, no `.tf` changes required.

### `.tfvars` — not used for the Jenkins-driven flow

Decision: skip `.tfvars` entirely for how Jenkins invokes this. Jenkins passes `customer_name` via `-var` flag (generated from the build parameter), and `instance_type`/other per-customer values come from the YAML file above — no file-based var injection needed in the pipeline.

`.tfvars` is optional purely as a **local testing convenience**, to avoid retyping `customer_name` interactively:
```
environments/uat/
├── terraform.tfvars.example    # committed, placeholder values only
├── terraform.tfvars            # gitignored, local test values
```
`.gitignore`: `*.tfvars` / `!*.tfvars.example`. None of the current variables are sensitive (no AWS credentials ever go in `.tfvars` — those come from env vars via `withCredentials`, unrelated to this file), so this is a convenience-only pattern, not a secrets-handling one.

## S3 State Backend — Bucket Already Exists, No Bootstrap Needed

**Correction from earlier draft:** this spec originally assumed the state bucket needed to be created (`bootstrap/` module). Confirmed via testing: **the bucket already exists** — `degito-opentofu-state`, region `ap-southeast-1`. Do not create a `bootstrap/` module or attempt to create this bucket. Simply reference it directly in `environments/uat/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket       = "degito-opentofu-state"
    region       = "ap-southeast-1"
    use_lockfile = true
    # key intentionally omitted — supplied by Jenkins via
    # -backend-config at `tofu init` time, per the state-isolation design above
  }
}
```

Confirmed working end-to-end: `tofu init -backend-config="key=uat/<customer>/terraform.tfstate"` → `tofu plan` → `tofu apply` → `tofu destroy`, full cycle tested successfully against this bucket.

### If bucket security settings ever need verification (not required now)

If it later turns out versioning/encryption/public-access-block aren't already configured on this bucket, that would be a **separate, one-off** `data "aws_s3_bucket"` + policy-resource config (read the existing bucket via data source, layer security resources on top) — not something to build speculatively now. Only revisit if there's an actual finding that the bucket lacks these protections.

### Explicit non-requirement

- Do not have `environments/uat` or `modules/uat-ec2` create or manage the state bucket — it already exists and is out of scope for this project's `.tf` code entirely.

## Validation Rules

- `customer_name`: regex `^[a-z0-9-]+$`, enforced via a `validation` block in `variables.tf`. This value is used unescaped in both the AWS tag and the S3 state key, so it must be constrained before it reaches either.
- No other validation required at this phase — keep it minimal.

## Explicit Non-Requirements / Things Not to Build Yet

- Do not implement a "check if state already exists before apply" guard inside OpenTofu itself — that check belongs in the Jenkins pipeline (via `aws s3api head-object`), not in `.tf` code.
- Do not implement destroy logic differences — `tofu destroy` against the correct per-customer state, invoked from the Delete Jenkins job, is sufficient. No special module-level teardown logic needed.
- Do not add provider-level multi-account/assume-role complexity unless asked.

## Resolved Decisions

- **Region: `ap-southeast-1`, not `ap-southeast-7`.** Earlier drafts assumed `ap-southeast-7` (Thailand); testing confirmed the actual VPC/subnet/security-group/S3 bucket all live in `ap-southeast-1` (Singapore). Corrected throughout this doc — use `ap-southeast-1` everywhere.
- **VPC/subnet:** reuse existing, confirmed values — VPC `vpc-09aa10f3b94994be4`, subnet `subnet-05de5976e810ae03a` (private, region `ap-southeast-1`). PoC approach: hardcoded as the `subnet_id` variable's default inside `modules/uat-ec2`. **Confirmed working** — successfully created and destroyed a real instance in this subnet.
- **Security group:** resolved — `sg-02b05989e0e617e14`, hardcoded default in the module, same pattern as `subnet_id`. **Confirmed working.**
- **AMI:** resolved as an `aws_ami` data source (auto-lookup latest Ubuntu), not a required `ami_id` variable. PoC simplification — see the note under Module Interface for how to promote this to a per-customer override later via the YAML config.
- **Private subnet → no public IP:** module outputs `private_ip`, not `public_ip`. Confirmed via test apply (`private_ip = "10.0.0.134"`).
- **S3 state bucket:** already exists (`degito-opentofu-state`, `ap-southeast-1`) — no `bootstrap/` creation needed, reference directly. Full `init → plan → apply → destroy` cycle tested successfully.
- **Per-customer config:** one YAML file per customer at `environments/uat/customers/<name>.yaml`, not a shared file. Jenkins only passes `customer_name`; `instance_type` (and future overrides) come from that file.
- **`.tfvars`:** not used in the Jenkins-driven flow (Jenkins uses `-var` + the YAML file above). Optional gitignored `terraform.tfvars` purely for local testing convenience — none of the current variables are sensitive.
- **Ansible/Docker/nginx phase:** still explicitly deferred — this spec covers instance creation only.

## Confirmed Working (tested end-to-end)

- `tofu init -input=false -backend-config="key=uat/<customer>/terraform.tfstate"` against the existing `degito-opentofu-state` bucket.
- `tofu plan` / `tofu apply` — successfully created `i-0953cf909ab58b592` with correct tags, subnet, security group, and `private_ip` output.
- `tofu destroy` — successfully tore down the same instance, matched state exactly (`0 to add, 0 to change, 1 to destroy`), no drift.
- **Full Jenkins pipeline run (not just local CLI)** — `create.Jenkinsfile` executed `tofu init` + `tofu plan` end-to-end inside the `ec2-provisioner` pod, passing only `-var=customer_name=hello-world`; `instance_type` was correctly pulled from `customers/hello-world.yaml` via the `main.tf` YAML-lookup pattern. Stage completed with `Finished: SUCCESS`, correct tags/subnet/SG in the plan output.

## Gotcha: CLI binary is `tofu`, not `opentofu`

The project/package is named OpenTofu, and the container image is `ghcr.io/opentofu/opentofu:1.8`, but **the actual executable inside that image is called `tofu`** — every command is `tofu init` / `tofu plan` / `tofu apply` / `tofu destroy`, never `opentofu ...`. This was confirmed during manual testing (every working command used `tofu`) and caught once as a bug in a generated Jenkinsfile that called `opentofu init`/`opentofu plan` — that fails with a command-not-found error. Double-check any pipeline `sh` step uses `tofu`, not `opentofu`, before assuming it'll run.

## Open Questions to Confirm Before/During Further Implementation

- Key pair / SSH access strategy — deferred to the Ansible phase; confirm the EC2 resource does not need a `key_name` argument yet (no SSH-based provisioning happening in this phase).
- Whether outbound internet (NAT Gateway) exists on this subnet's route table — not required for this phase, but worth confirming ahead of the Ansible phase so it isn't a surprise later.
- Whether/when `ami_id` needs to become a real per-customer override (via the YAML config) rather than always auto-resolving to latest Ubuntu — currently a PoC simplification, not yet a real gap, since no customer has needed a different AMI so far.
- **`ami_id` — resolved, not a live bug.** Earlier drafts of this spec flagged a silent-failure risk (Jenkinsfile passing `-var "ami_id=$AMI_ID"` while `main.tf`/`variables.tf` never wired it through). **Correction:** confirmed against the current `create.Jenkinsfile` — that conditional `ami_id` flag no longer exists; the pipeline now only passes `-var="customer_name=$CUSTOMER_NAME"`, consistent with `main.tf` and `variables.tf` as they actually stand today. The earlier note was accurate for a prior version of the Jenkinsfile but is stale now — no `ami_id` override path exists anywhere in the current pipeline or `.tf` code, and nothing is silently ignoring it, since nothing is being passed. If per-customer AMI overrides become a real requirement later, this is a from-scratch feature (add `ami_id` to `main.tf`'s module call, sourced from `local.customer_config.ami_id`, with the existing `aws_ami` data source as its fallback), not a bug fix.
- Jenkins pipeline wiring: `Create` job needs to pass `-var="customer_name=..."` and ensure `customers/<name>.yaml` exists (or is generated) before `tofu apply` runs — not yet built, next step after this spec.