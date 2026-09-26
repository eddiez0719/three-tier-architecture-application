data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/orderhub:${var.image_tag}"
}

module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "~> 5.0"
    name = "${var.env}-orderhub"
    cidr = var.vpc_cidr
    azs = ["ap-southeast-2a", "ap-southeast-2b"]
    public_subnets = [cidrsubnet (var.vpc_cidr, 8, 0), cidrsubnet(var.vpc_cidr, 8, 1)]
    private_subnets = [cidrsubnet (var.vpc_cidr, 8, 2), cidrsubnet(var.vpc_cidr, 8, 3)]
    database_subnets = [cidrsubnet (var.vpc_cidr, 8, 4), cidrsubnet(var.vpc_cidr, 8, 5)]
    enable_nat_gateway = true
    single_nat_gateway = true
}

resource "aws_security_group" "alb" {
    name = "${var.env}-orderhub-alb-sg"
    description = "Allow HTTP from the internet"
    vpc_id = module.vpc.vpc_id
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "app" {
    name = "${var.env}-orderhub-app-sg"
    description = "Allow 8080 from ALB only"
    vpc_id = module.vpc.vpc_id
    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        security_groups = [aws_security_group.alb.id]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "db" {
    name = "${var.env}-orderhub-db-sg"
    description = "Allow MYSQL from app only"
    vpc_id = module.vpc.vpc_id
    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        security_groups = [aws_security_group.app.id]
    }
}

resource "aws_rds_cluster" "this" {
    cluster_identifier = "${var.env}-orderhub-db-cluster"
    engine = "aurora-mysql"
    database_name = "orderhub"
    master_username = "orderadmin"
    manage_master_user_password = true
    db_subnet_group_name = module.vpc.database_subnet_group_name
    vpc_security_group_ids = [aws_security_group.db.id]
    storage_encrypted = true
    skip_final_snapshot = true
    serverlessv2_scaling_configuration {
        min_capacity = 0.5
        max_capacity = var.db_max_acu
    }
}

resource "aws_rds_cluster_instance" "this" {
    count = var.db_instance_count
    identifier = "${var.env}-orderhub-${count.index + 1}"
    cluster_identifier = aws_rds_cluster.this.id
    instance_class = "db.serverless"
    engine = aws_rds_cluster.this.engine
    engine_version = aws_rds_cluster.this.engine_version
}

resource "aws_lb" "this" {
    name = "${var.env}-orderhub-alb"
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb.id]
    subnets = module.vpc.public_subnets
}

resource "aws_lb_target_group" "app" {
    name = "${var.env}-orderhub-alb-tg"
    port                 = 8080  
    protocol             = "HTTP"
    target_type          = "ip"
    vpc_id               = module.vpc.vpc_id
    deregistration_delay = 10
    health_check {  
        path = "/health"
        interval = 10
        healthy_threshold = 2
    }
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.this.arn
    port = 80
    protocol = "HTTP"
    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.app.arn
    }
}

resource "aws_ecs_cluster" "this" {
    name = "${var.env}-orderhub"
}

resource "aws_iam_role" "exec" {
    name = "${var.env}-orderhub-exec-role"
    assume_role_policy = jsonencode ( {
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Principal = { Service = "ecs-tasks.amazonaws.com"}
            Action = "sts:AssumeRole"
        }]
    })
}

resource "aws_iam_role_policy_attachment" "exec" {
    role = aws_iam_role.exec.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "read_db_secret" {
    name = "read-db-secret"
    role = aws_iam_role.exec.id
    policy = jsonencode ( {
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Action = "secretsmanager:GetSecretValue"
            Resource = aws_rds_cluster.this.master_user_secret[0].secret_arn
        }]
    })
}

resource "aws_cloudwatch_log_group" "app" {
    name              = "/ecs/${var.env}-orderhub"
    retention_in_days = 14
}

resource "aws_ecs_task_definition" "app" {
    family = "${var.env}-orderhub"
    requires_compatibilities = ["FARGATE"]
    network_mode = "awsvpc"
    cpu = var.task_cpu
    memory = var.task_memory
    execution_role_arn = aws_iam_role.exec.arn
    container_definitions = jsonencode ([{
            name         = "app"   
            image        = local.image
            essential    = true
            portMappings = [{ containerPort = 8080 }]
            environment = [
                { name = "APP_ENV", value = var.env }, 
                { name = "APP_VERSION", value = var.image_tag }, 
                { name = "DB_HOST", value = aws_rds_cluster.this.endpoint },
                { name = "DB_NAME", value = aws_rds_cluster.this.database_name } 
            ]
            secrets = [
                { name = "DB_USER", valueFrom = "${aws_rds_cluster.this.master_user_secret[0].secret_arn}:username::" },
                { name = "DB_PASSWORD", valueFrom = "${aws_rds_cluster.this.master_user_secret[0].secret_arn}:password::" }
            ]
            logConfiguration = {
                logDriver = "awslogs"
                options = {
                    "awslogs-group" = aws_cloudwatch_log_group.app.name
                    "awslogs-region" = data.aws_region.current.name
                    "awslogs-stream-prefix" = "app"
                }
            }
    }])
}

resource "aws_ecs_service" "app" {
    name            = "${var.env}-orderhub"  
    cluster = aws_ecs_cluster.this.id
    task_definition = aws_ecs_task_definition.app.arn
    desired_count   = var.desired_count 
    launch_type     = "FARGATE"
    network_configuration { 
       subnets          = module.vpc.private_subnets
       security_groups  = [aws_security_group.app.id]
       assign_public_ip = false  
    }
    load_balancer {
        target_group_arn = aws_lb_target_group.app.arn
        container_name   = "app" 
        container_port   = 8080  
    }
    health_check_grace_period_seconds = 30
    deployment_circuit_breaker {
        enable   = true
        rollback = true 
    }
    depends_on = [ 
        module.vpc, 
        aws_lb_listener.http,
        aws_rds_cluster_instance.this,
        aws_iam_role_policy_attachment.exec,
        aws_iam_role_policy.read_db_secret,
    ]
}
