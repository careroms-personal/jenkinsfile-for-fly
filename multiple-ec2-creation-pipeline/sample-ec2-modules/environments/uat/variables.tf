variable "customer_name" {
  type        = string
  description = "Customer identifier. The only value Jenkins passes in via -var; used to look up customers/<name>.yaml for the rest of this customer's config."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "customer_name must contain only lowercase letters, numbers, and hyphens."
  }
}
