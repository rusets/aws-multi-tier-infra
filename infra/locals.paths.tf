############################################
# Path locals — repo-relative references
############################################
locals {
  repo_root     = abspath("${path.root}/..")
  app_dir       = "${local.repo_root}/app"
  bootstrap_dir = "${local.repo_root}/bootstrap"
  build_dir     = "${local.repo_root}/build"

  app_zip_path = "${local.build_dir}/app.zip"
  user_data    = "${local.bootstrap_dir}/user_data.sh"
}
