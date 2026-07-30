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
- No multi-region support — single region (`ap-southeast-1`) for now.

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
        ├── main.tf            (calls module "uat-ec2")
        ├── variables.tf        (customer_name, instance_type, ami_id, ...)
        ├── backend.tf          (partial S3 backend config — key injected at init time)
        └── versions.tf
```

### Design rules

1. **`modules/uat-ec2` has no backend block.** Modules never define backends — only root/caller configs do.
2. **`environments/uat/backend.tf` uses a partial backend configuration.** Do not hardcode the state `key`. It must be supplied at `tofu init` time via `-backend-config`, e.g.:
   ```
   tofu init -reconfigure \
     -backend-config="key=uat/${CUSTOMER_NAME}/terraform.tfstate" \
     -backend-config="encrypt=true"
   ```
   This is how one-state-per-customer isolation is enforced — there is exactly one caller config, invoked N times with N different state keys, never N copies of the directory.
3. **State backend:** S3, with OpenTofu 1.8+ native locking (`use_lockfile = true`) — no DynamoDB table required.
4. **`environments/uat` is a thin caller.** One `module "this" { source = "../../modules/uat-ec2" ... }` block. All variables passed straight through from Jenkins-supplied values (`-var` flags or generated `.tfvars`). No business logic lives here beyond wiring.

## Module Interface (`modules/uat-ec2`)

### Inputs (`variables.tf`)

| Variable | Type | Required | Notes |
|---|---|---|---|
| `customer_name` | string | yes | Identifier used for naming, tags, and (at the caller level) the state key. Must validate against `^[a-z0-9-]+$` (lowercase alphanumeric + hyphens only) — this value flows into the AWS resource `Name` tag and the S3 state path. |
| `instance_type` | string | yes | e.g. `t3.micro`. Varies per customer's setup process. No default — must be explicit per the business requirement. |
| `ami_id` | string | no | Varies per customer when supplied. If omitted, defaults to the latest Ubuntu LTS AMI, resolved via a `data "aws_ami"` lookup inside the module (owner `099720109477` Canonical, `most_recent = true`) rather than a hardcoded AMI ID — keeps the fallback current as new LTS point releases ship. Architecture is derived from `instance_type`: Graviton families (`t4g`, `m6g`, `c6g`, `c7g`, ...) resolve an `arm64` AMI, everything else resolves `amd64` — required so the AMI's CPU architecture always matches the instance type. |
| `subnet_id` | string | no | ID of an **existing, private** subnet the instance launches into: `subnet-05de5976e810ae03a` (VPC `vpc-09aa10f3b94994be4`). PoC decision: hardcoded as the variable's `default` in `modules/uat-ec2/variables.tf` rather than passed from the caller — same subnet is reused for every customer's UAT for now. To promote this to a real per-caller input later, just remove the `default`; no other refactor needed. No public IP is assigned (private subnet) — see Outputs note below. |
| `security_group_id` | string | no | ID of an existing security group to attach: `sg-02b05989e0e617e14`. Same PoC pattern as `subnet_id` — hardcoded as the variable's `default`; remove the default later to make it a real per-caller input. |

> Keep the input surface minimal beyond this. Do not add further speculative variables (key_pair_name, volume_size, security_group_id, etc.) until there's a real requirement — bake sensible fixed defaults into the module internals instead, and promote them to variables only when a customer actually needs to override.

> Note on `vpc_id`: not taken as a direct module input — a subnet is always scoped to exactly one VPC, so `subnet_id` alone is sufficient for `aws_instance` placement. If a security group needs to be looked up/created later, derive `vpc_id` from the subnet via a `data "aws_subnet"` lookup inside the module rather than adding a redundant `vpc_id` variable.

### Resources (`main.tf`)

- One `aws_instance` resource per module call, using `var.subnet_id` and `[var.security_group_id]` for `vpc_security_group_ids`.
- No `key_name` argument — SSH/key-pair strategy is deferred to the Ansible phase (out of scope here); the instance launches without an assigned key pair for now.
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

- `variables.tf`: same three inputs (`customer_name`, `instance_type`, `ami_id`), no defaults, passed straight to the module.
- `main.tf`: single module block invoking `modules/uat-ec2`.
- `backend.tf`: partial S3 backend (bucket + region only; `key` and `encrypt` supplied at init time by the caller/Jenkins).
- `versions.tf`: pin OpenTofu and AWS provider versions (use current stable AWS provider; do not pin to an old major version without checking).

## S3 State Backend — Bootstrap Required

Confirmed: **the S3 bucket for state storage does not exist yet.** This creates a chicken-and-egg problem worth calling out explicitly so Claude Code doesn't try to solve it inside the main module:

> `environments/uat` stores its state *in* an S3 bucket — but that bucket itself needs to be created by *something*. It cannot be created by `environments/uat` using the same S3 backend, because the backend can't exist before the bucket does.

### Required structure addition

```
opentofu/
├── bootstrap/                 # NEW — one-time setup, run manually or via a separate Jenkins job
│   ├── main.tf                 (aws_s3_bucket for state, with versioning enabled)
│   ├── variables.tf
│   └── backend.tf              (local backend — this state stays local or in a
│                                 separate already-existing bucket; not the bucket
│                                 it's creating)
├── modules/
│   └── uat-ec2/
└── environments/
    └── uat/
```

### `bootstrap/` requirements

- Creates exactly one `aws_s3_bucket` resource for OpenTofu state storage.
- **Enable versioning** (`aws_s3_bucket_versioning`) — protects against accidental state corruption/overwrite, cheap insurance given this bucket holds every customer's state.
- Enable default encryption (`aws_s3_bucket_server_side_encryption_configuration`, SSE-S3 or SSE-KMS — SSE-S3 is sufficient unless there's a compliance requirement for KMS).
- **Block public access** (`aws_s3_bucket_public_access_block`, all four settings `true`) — this bucket contains infrastructure state, must never be public.
- Uses a **local backend** for its own state (`bootstrap/terraform.tfstate` committed to git is *not* recommended — instead run bootstrap once, keep its local state file somewhere safe/out of git via `.gitignore`, or use a separate pre-existing bucket outside this project if one exists). This is a one-time, rarely-re-run operation — not part of the Jenkins Create/Delete pipelines.
- This is run **once, manually, before `environments/uat` is ever used** — not part of the per-customer Jenkins pipeline. Document this clearly as a manual pre-requisite step, e.g. in a `bootstrap/README.md`.

### `environments/uat/backend.tf` — reference the bootstrapped bucket

```hcl
terraform {
  backend "s3" {
    bucket       = "<bucket name output by bootstrap>"
    region       = "ap-southeast-1"
    use_lockfile = true
    # key and encrypt intentionally omitted — supplied by Jenkins via
    # -backend-config at `tofu init` time, per the state-isolation design above
  }
}
```

### Explicit non-requirement

- Do not have `environments/uat` or `modules/uat-ec2` create or manage the state bucket itself — that responsibility belongs entirely to `bootstrap/` and must not be mixed into the per-customer apply/destroy flow.

## Validation Rules

- `customer_name`: regex `^[a-z0-9-]+$`, enforced via a `validation` block in `variables.tf`. This value is used unescaped in both the AWS tag and the S3 state key, so it must be constrained before it reaches either.
- No other validation required at this phase — keep it minimal.

## Explicit Non-Requirements / Things Not to Build Yet

- Do not implement a "check if state already exists before apply" guard inside OpenTofu itself — that check belongs in the Jenkins pipeline (via `aws s3api head-object`), not in `.tf` code.
- Do not implement destroy logic differences — `tofu destroy` against the correct per-customer state, invoked from the Delete Jenkins job, is sufficient. No special module-level teardown logic needed.
- Do not add provider-level multi-account/assume-role complexity unless asked.

## Resolved Decisions

- **VPC/subnet:** reuse existing, confirmed values — VPC `vpc-09aa10f3b94994be4`, subnet `subnet-05de5976e810ae03a` (private). PoC approach: hardcoded as the `subnet_id` variable's default inside `modules/uat-ec2` (see Inputs table). Real deployment: Jenkins (k8s) and all EC2 instances share this same subnet/VPC, so no bastion/VPN is needed for future in-VPC reachability (e.g. Ansible).
- **Private subnet → no public IP:** module outputs `private_ip`, not `public_ip`. `public_ip` would always be null for this subnet and is not implemented.
- **Ansible/Docker/nginx phase:** explicitly deferred (unchanged from original Non-Goals) — this spec covers instance creation only. Since NAT Gateway/outbound-internet reachability only matters once Ansible needs to install software on the instance, it is *not* a blocker for this phase and does not need to be verified before implementing the OpenTofu module.
- **S3 state bucket:** does not exist yet — a `bootstrap/` OpenTofu config (separate from the main module/caller, run once manually) creates it. See "S3 State Backend — Bootstrap Required" section above.
- **AMI fallback:** `ami_id` is optional — when omitted, the module resolves the latest Ubuntu LTS AMI via a `data "aws_ami"` lookup (see Inputs table), architecture-matched to `instance_type` (arm64 for Graviton families like `t4g`, amd64 otherwise) rather than a fixed AMI ID.
- **First real customer instance type:** `t4g.micro` (Graviton/arm64) — the reason the AMI fallback needed to be architecture-aware rather than a fixed amd64 lookup.
- **Security group:** confirmed, existing group reused — `sg-02b05989e0e617e14`. Same PoC pattern as `subnet_id`: hardcoded as the `security_group_id` variable's default.
- **Key pair / SSH access:** confirmed deferred to the Ansible phase. No `key_name` on the `aws_instance` in this phase.
- **Region:** confirmed `ap-southeast-1` (not `ap-southeast-7` as earlier assumed).
- **S3 bucket name:** confirmed `degito-opentofu-state`.

## Open Questions to Confirm Before/During Implementation

- Whether outbound internet (NAT Gateway) exists on this subnet's route table — not required for this phase, but worth confirming ahead of the Ansible phase so it isn't a surprise later.