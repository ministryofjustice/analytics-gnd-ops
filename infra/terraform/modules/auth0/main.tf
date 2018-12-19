provider "auth0" {
  domain        = "${var.auth0_tenant_domain}"
  client_id     = "${var.auth0_api_client_id}"
  client_secret = "${var.auth0_api_client_secret}"
}

resource "auth0_client" "aws" {
  name        = "test-AWS"
  description = "SAML provider used for 'Open in AWS'"
  app_type    = "regular_web"
  callbacks   = [
    "https://signin.aws.amazon.com/saml",
    "https://aws.services.${var.env}.${var.root_domain}/callback",
  ]
  allowed_origins = [
    "https://aws.services.${var.env}.${var.root_domain}",
  ]
}

resource "auth0_client" "kubectl-oidc" {
  name      = "test-kubectl-oidc"
  app_type  = "regular_web"
  callbacks = [
    "http://localhost:3000/callback",
    "https://cpanel-master.services.${var.env}.${var.root_domain}/callback",
  ]
  allowed_origins = [
    "http://localhost:3000",
    "https://cpanel-master.services.${var.env}.${var.root_domain}",
  ]
  allowed_logout_urls = [
    "http:/localhost:3000",
    "https://cpanel-master.services.${var.env}.${var.root_domain}",
  ]
}

resource "auth0_connection" "github" {
  name = "test-github"
  strategy = "github"
  options  = {
    configuration = {
      client_id     = "${var.github_oauth_client_id}"
      client_secret = "${var.github_oauth_client_secret}"
      profile       = true
      email         = true
      read_user     = true
      read_org      = true
      scope         = "user:email,read:user,read:org"
    }
  }
  enabled_clients = [
    "${auth0_client.aws.id}",
    "${auth0_client.kubectl-oidc.id}",
  ]
}

locals {
  auth0_rules_config = "${map(
    "AWS_ACCOUNT_ID",          "${var.aws_account_id}",
    "ENV",                     "${var.env}",
  )}"
}

resource "auth0_rule_config" "config" {
  count = "${length(keys(local.auth0_rules_config))}"
  key   = "${element(keys(local.auth0_rules_config), count.index)}"
  value = "${element(values(local.auth0_rules_config), count.index)}"
}

variable "auth0_rules" {
  default = [
    "auth0-authorization-extension",
    "aws-saml-role-mapping",
    "whitelist-google-domains",
    "whitelist-github-orgs",
    "Multifactor-Google-Authenticator-Do-Not-Rename",
    "add-group-claim-to-token",
    "lowercase-user-nickname",
  ]
}

resource "auth0_rule" "rule" {
  count  = "${length(var.auth0_rules)}"
  name   = "${element(var.auth0_rules, count.index)}"
  order  = "${count.index}"
  script = "${file("${path.module}/rules/${element(var.auth0_rules, count.index)}.js")}"
}
