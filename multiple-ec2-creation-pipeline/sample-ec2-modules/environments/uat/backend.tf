# Partial backend configuration — do not add `key` or `encrypt` here.
# They are supplied at `tofu init` time via -backend-config, e.g.:
#
#   tofu init -reconfigure \
#     -backend-config="key=uat/${CUSTOMER_NAME}/terraform.tfstate" \
#     -backend-config="encrypt=true"
#
# This is how one-state-per-customer isolation is enforced.
terraform {
  backend "s3" {
    bucket       = "degito-opentofu-state" # output of bootstrap/, confirm before first use
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}
