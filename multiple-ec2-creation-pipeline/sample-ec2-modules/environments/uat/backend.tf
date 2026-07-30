# Partial backend configuration — do not add `key` here.
# It is supplied at `tofu init` time via -backend-config, e.g.:
#
#   tofu init -input=false \
#     -backend-config="key=uat/${CUSTOMER_NAME}/terraform.tfstate"
#
# This is how one-state-per-customer isolation is enforced.
# Bucket already exists (degito-opentofu-state) — no bootstrap module needed.
terraform {
  backend "s3" {
    bucket       = "degito-opentofu-state"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}
