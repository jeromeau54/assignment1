# ec2/terragrunt.hcl
# Inherits root remote state and provider; passes variable values to Terraform.

include "root" {
  path = find_in_parent_folders()
}

terraform {
  extra_arguments "common_vars" {
    commands  = get_terraform_commands_that_need_vars()
    arguments = ["-var-file=${get_parent_terragrunt_dir()}/terraform.tfvars"]
  }
}

inputs = {
  instance_type  = "t3.micro"
  key_name       = "assignment1-key"
  db_name        = "node_crud"
  db_user        = "nodeapp"
  key_output_dir = get_parent_terragrunt_dir()
}
