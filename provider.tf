terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.22.0"
    }
  }
}

provider "aws" {
  profile = "default"  
  region  = "us-west-2"
	default_tags {
		tags = {
			Name = "JSR"
		}
	}
}

provider "aws" {
	alias = "east"
	region = "us-east-1"
}
