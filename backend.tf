# Cloud Shell's copy only. Cloud Shell opens this repository in a temporary session whose home folder is deleted when
# it ends, so Terraform keeps its state in a bucket in your project (the tutorial makes it; it is private to you).
terraform {
  backend "gcs" {}
}
