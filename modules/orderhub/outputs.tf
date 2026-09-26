output "alb_url" {
    value = "http://${aws_lb.this.dns_name}"
}

output "ecs_cluster" {
    value = aws_ecs_cluster.this.name
}

output "db_endpoint" { 
    value = aws_rds_cluster.this.endpoint
}