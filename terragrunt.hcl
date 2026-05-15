# Root terragrunt.hcl
# Stores Terraform state locally on this machine (gitignored via tfstate/).

remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_parent_terragrunt_dir()}/tfstate/${path_relative_to_include()}/terraform.tfstate"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region  = "ap-southeast-1"
  profile = "assignment1"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
EOF
}
