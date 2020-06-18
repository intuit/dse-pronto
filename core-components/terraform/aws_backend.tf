# default provider (no alias) for current deployment
provider "aws" {
  region   = "#region#"
}

# aliased provider for interacting with tfstate bucket
provider "aws" {
  alias    = "tfstate"
  region   = "#tfstate_region#"
}

terraform {
  backend "s3" {
    bucket   = "#bucket#"
    key      = "#key#"
    region   = "#tfstate_region#"
  }
}
