############################################
# TFLint — Terraform ruleset
############################################
plugin "terraform" {
  enabled = true
  preset  = "all"
}

############################################
# Global TFLint configuration
############################################
config {
  call_module_type = "all"
}
