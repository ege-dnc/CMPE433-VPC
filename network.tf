# ─────────────────────────────────────────────
# VPC & Network Configuration
# ─────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "farmer-app-vpc"
    Project = "agri-coop"
  }
}

# Subnets — one public, one private
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "farmer-app-public-subnet"
    Project = "agri-coop"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name    = "farmer-app-private-subnet"
    Project = "agri-coop"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "farmer-app-igw"
    Project = "agri-coop"
  }
}

# Route Tables & Associations
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "farmer-app-public-rt"
    Project = "agri-coop"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "farmer-app-private-rt"
    Project = "agri-coop"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────
resource "aws_security_group" "web" {
  name        = "farmer-app-web-sg"
  description = "Allow web traffic to public subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "farmer-app-web-sg"
    Project = "agri-coop"
  }
}

resource "aws_security_group" "backend" {
  name        = "farmer-app-backend-sg"
  description = "Allow traffic only from public subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "FastAPI from public subnet only"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "farmer-app-backend-sg"
    Project = "agri-coop"
  }
}

# ─────────────────────────────────────────────
# Storage Service 
# ─────────────────────────────────────────────
resource "aws_s3_object" "farmer_csv" {
  # Dynamically hooks bucket
  bucket = var.target_s3_bucket_name
  key    = "data/farmers_data.csv"
  source = "${path.module}/farmers_data.csv"
  etag   = filemd5("${path.module}/farmers_data.csv")

  tags = {
    Project = "agri-coop"
  }
}

# ─────────────────────────────────────────────
# Alerts & Notification (SNS)
# ─────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "farmer-app-alerts"

  tags = {
    Project = "agri-coop"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─────────────────────────────────────────────
# CloudWatch Metric Alarm
# ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "farmer-app-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when EC2 CPU exceeds 80% for 2 consecutive periods"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.iaas_instance_id
  }

  tags = {
    Project = "agri-coop"
  }
}

# ─────────────────────────────────────────────
# CloudWatch Dashboard
# ─────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "farmer-app-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          region = var.aws_region
          title  = "EC2 CPU Utilization"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", "${var.iaas_instance_id}"]
          ]
          view = "timeSeries"
        }
      },
      {
        type = "metric"
        properties = {
          region = var.aws_region
          title  = "S3 Bucket Size"
          period = 86400
          stat   = "Average"
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", "${var.target_s3_bucket_name}", "StorageType", "StandardStorage"]
          ]
          view = "timeSeries"
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  value = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=farmer-app-dashboard"
}