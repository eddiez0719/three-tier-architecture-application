terraform {
    required_version = ">= 1.10.0"
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.0"
        }
        grafana = {
            source = "grafana/grafana"
            version = "~> 4.0"
        }
    }
    backend "s3" {
        bucket = "distinctioncoding-tfstatefilebucket"
        region = "ap-southeast-2"
        encrypt = true
        use_lockfile = true
    }
}

provider "aws" {
    region = "ap-southeast-2"
}

provider "grafana" {

}

data "aws_region" "current" {

}

data "aws_lb" "orderhub" {
    name = "${var.env}-orderhub-alb"
}

data "aws_cloudwatch_log_group" "orderhub" {
    name = "/ecs/${var.env}-orderhub"
}

locals {
    alb_dimension = data.aws_lb.orderhub.arn_suffix
    ecs_cluster = "${var.env}-orderhub"
    ecs_service = "${var.env}-orderhub"
    db_cluster = "${var.env}-orderhub-db-cluster"
}

resource "aws_iam_user" "grafana" {
    name = "${var.env}-grafana-cloudwatch"
}

resource "aws_iam_user_policy" "grafana_read" {
    name = "cloudwatch-read-only"
    user = aws_iam_user.grafana.name
    policy = jsonencode ({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "cloudwatch:DescribeAlarmsForMetric",
                    "cloudwatch:DescribeAlarmHistory",
                    "cloudwatch:DescribeAlarms",
                    "cloudwatch:ListMetrics", 
                    "cloudwatch:GetMetricData",
                    "cloudwatch:GetInsightRuleReport"
                ]
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = "pi:GetResourceMetrics"
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = [
                    "logs:DescribeLogGroups", 
                    "logs:ListAggregateLogGroupSummaries", 
                    "logs:GetLogGroupFields", 
                    "logs:StartQuery",   
                    "logs:StopQuery",
                    "logs:GetQueryResults", 
                    "logs:GetLogEvents"
                ]
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = [
                    "ec2:DescribeTags", 
                    "ec2:DescribeInstances",
                    "ec2:DescribeRegions", 
                    "tag:GetResources" 
                ]
                Resource = "*"
            }
        ]
    })
}

resource "aws_iam_access_key" "grafana" {
    user = aws_iam_user.grafana.name
}

resource "grafana_data_source" "cloudwatch" {
    name = "Cloudwatch ${var.env}"
    type = "cloudwatch"
    json_data_encoded = jsonencode ({
        authType = "keys"
        defaultRegion = data.aws_region.current.name
    })
    secure_json_data_encoded = jsonencode ({
        accessKey = aws_iam_access_key.grafana.id
        secretKey = aws_iam_access_key.grafana.secret
    })
}

resource "grafana_folder" "orderhub" {
    title = "OrderHub ${var.env}"
}

resource "grafana_contact_point" "email" {
    name = "OrderHub ${var.env} email"
    email {
        addresses = [var.alert_email]
    }
}

resource "grafana_rule_group" "orderhub" {
    name             = "orderhub-${var.env}"
    folder_uid       = grafana_folder.orderhub.uid
    interval_seconds = 60

    rule {
        name           = "${var.env} OrderHub 4xx Spike"
        condition      = "C"
        for            = "0s"
        no_data_state  = "OK"
        exec_err_state = "Error"
        labels = {
            env = var.env
        }
        annotations = {
            summary = "OrderHub ${var.env}: more than 10 HTTP 4xx responses in one minute"
        }
        notification_settings {
            contact_point = grafana_contact_point.email.name
        }

        data {
            ref_id         = "A"
            datasource_uid = grafana_data_source.cloudwatch.uid
            relative_time_range {
                from = 300
                to   = 0
            }
            model = jsonencode({
                refId            = "A"
                queryMode        = "Metrics"
                region           = data.aws_region.current.name
                namespace        = "AWS/ApplicationELB"
                metricName       = "HTTPCode_Target_4XX_Count"
                dimensions       = { LoadBalancer = local.alb_dimension }
                statistic        = "Sum"
                period           = "60"
                matchExact       = true
                metricQueryType  = 0
                metricEditorMode = 0
            })
        }

        data {
            ref_id         = "B"
            datasource_uid = "__expr__"
            relative_time_range {
                from = 0
                to   = 0
            }
            model = jsonencode({
                refId      = "B"
                datasource = { type = "__expr__", uid = "__expr__" }
                type       = "reduce"
                expression = "A"
                reducer    = "max"
            })
        }

        data {
            ref_id         = "C"
            datasource_uid = "__expr__"
            relative_time_range {
                from = 0
                to   = 0
            }
            model = jsonencode({
                refId      = "C"
                datasource = { type = "__expr__", uid = "__expr__" }
                type       = "threshold"
                expression = "B"
                conditions = [{
                    evaluator = {
                        type   = "gt"
                        params = [10]
                    }
                }]
            })
        }
    }
}

output "dashboard_url" {
    value = grafana_dashboard.orderhub.url
}