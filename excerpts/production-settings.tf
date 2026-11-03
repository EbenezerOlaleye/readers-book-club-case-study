# Excerpt from the private Readers Book Club repository (infrastructure/terraform/envs/production/main.tf).
# The rest of the file wires these settings into the shared modules: network, redis, media,
# secrets, alb, ecs and monitoring. envs/staging/main.tf is identical except for this block.

# Production: two of everything across two availability zones.
# Only the `settings` block differs between envs/staging and envs/production.

locals {
  environment = "production"
  name        = "rbc-${local.environment}"

  settings = {
    vpc_cidr            = "10.0.0.0/16"
    nat_gateway_count   = 2
    redis_node_type     = "cache.t4g.small"
    redis_node_count    = 2
    redis_snapshot_days = 7
    use_fargate_spot    = false
    frontend            = { cpu = 512, memory = 1024, min_count = 2, max_count = 4 }
    backend             = { cpu = 512, memory = 1024, min_count = 2, max_count = 6 }
    log_retention_days  = 30
    deletion_protection = true
    force_destroy_media = false
    secret_recovery     = 7
    # "false" while SES is in its sandbox: sign-up then signs people in
    # without an activation email. Set "true" once SES production access is
    # granted, then apply and deploy.
    require_email_verification = "false"
