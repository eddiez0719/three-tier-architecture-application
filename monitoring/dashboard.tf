locals {
    ds = {
        type = "cloudwatch"
        uid = grafana_data_source.cloudwatch.uid
    }
    cw = {
        datasource = local.ds
        queryMode        = "Metrics" 
        region           = data.aws_region.current.name
        period           = "60" 
        matchExact       = true
        metricQueryType  = 0
        metricEditorMode = 0
    }
    alb_dims = { LoadBalancer = local.alb_dimension } 
    ecs_dims = { ClusterName = local.ecs_cluster, ServiceName = local.ecs_service }
    db_dims  = { DBClusterIdentifier = local.db_cluster } 

}

resource "grafana_dashboard" "orderhub" {
    folder = grafana_folder.orderhub.uid 
    config_json = jsonencode ({
        uid      = "orderhub-${var.env}" 
        title    = "OrderHub ${var.env}" 
        tags     = ["orderhub", var.env]
        timezone = "browser"  
        refresh  = "15s"   
        time     = { from = "now-30m", to = "now" } 
        panels = [
            {
                id         = 1 
                type       = "timeseries"
                title      = "Traffic - ALB requests / min"
                datasource = local.ds
                gridPos    = { x = 0, y = 0, w = 12, h = 8 } 
                targets = [
                    merge(local.cw, { refId = "A", namespace = "AWS/ApplicationELB", metricName = "RequestCount", dimensions = local.alb_dims, statistic = "Sum", label = "requests" })
                ]
            },
            {
                id = 2
                type        = "timeseries"  
                title       = "Latency - p95 response time"
                datasource  = local.ds   
                gridPos     = { x = 12, y = 0, w = 12, h = 8 }
                fieldConfig = { defaults = { unit = "s" }, overrides = [] }
                targets = [
                    merge(local.cw, { refId = "A", namespace = "AWS/ApplicationELB", metricName = "TargetResponseTime", dimensions = local.alb_dims, statistic = "p95", label = "p95" })
                ]
            },
            {
                id = 3 
                type       = "timeseries" 
                title      = "Errors - HTTP 4xx / 5xx per min"
                datasource = local.ds
                gridPos    = { x = 0, y = 8, w = 12, h = 8 }
                targets = [
                    merge(local.cw, { refId = "A", namespace = "AWS/ApplicationELB", metricName = "HTTPCode_Target_4XX_Count", dimensions = local.alb_dims, statistic = "Sum", label = "4xx" }),
                    merge(local.cw, { refId = "B", namespace = "AWS/ApplicationELB", metricName = "HTTPCode_Target_5XX_Count", dimensions = local.alb_dims, statistic = "Sum", label = "5xx" })
                ]
            }
        ]
    })
} 