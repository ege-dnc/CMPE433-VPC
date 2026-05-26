variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target AWS region"
}

variable "target_s3_bucket_name" {
  type        = string
  default     = "farmer-app-data"
}

variable "alert_email" {
  type        = string
  default     = "your-real-email@domain.com" # Put your email address here
  description = "Destination address for monitoring alarms"
}

variable "iaas_instance_id" {
  type        = string
  default     = "i-placeholder123456" # Replace this with frontend EC2 runtime ID
  description = "The targeted EC2 ID to trace metrics"
}