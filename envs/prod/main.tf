terraform {
    required_version = ">= 1.10.0"
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
backend "s3" {
    bucket = "distinctioncoding-tfstatefilebucket"
    key = "prod/orderhub/terraform.tfstate"
    region = "ap-southeast-2"
    encrypt = true
    use_lockfile = true 
    }
}

provider "aws" {
    region = "ap-southeast-2"
    default_tags {
         tags = {
            Project = "orderhub"
            Environment = "prod"
         }
    }
}

module "orderhub" {
    source = "../../modules/orderhub"
    env = "prod"
    vpc_cidr="10.20.0.0/16"
    image_tag = "v1"
    desired_count= 2
    task_cpu=512
    task_memory=1024
    db_instance_count=2
    db_max_acu=4
}

output "alb_url" {
    value = module.orderhub.alb_url
}

output "ecs_cluster" {
    value= module.orderhub.ecs_cluster
}