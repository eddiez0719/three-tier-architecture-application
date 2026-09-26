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
    key = "dev/orderhub/terraform.tfstate"
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
            Environment = "dev"
         }
    }
}

module "orderhub" {
    source = "../../modules/orderhub"
    env = "dev"
    vpc_cidr="10.10.0.0/16"
    image_tag = "v1"
    desired_count= 1
    task_cpu=256
    task_memory=512
    db_instance_count=1
    db_max_acu=1
}

output "alb_url" {
    value = module.orderhub.alb_url
}

output "ecs_cluster" {
    value= module.orderhub.ecs_cluster
}