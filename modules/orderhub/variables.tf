variable "env" {
    type = string
}

variable "vpc_cidr" {
    type = string
}

variable "image_tag" {
    type = string
}

variable "desired_count" { 
    type = number
}

variable "task_cpu" {
    type = number
}

variable "task_memory" {
    type = number
}

variable "db_instance_count" { 
    type = number
}

variable "db_max_acu" { 
    type = number
}