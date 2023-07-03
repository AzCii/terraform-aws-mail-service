output "mail_bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.mail.arn
}

output "mail_lambda_arn" {
  description = "The Amazon Resource Name (ARN) identifying your Lambda Function."
  value       = aws_lambda_function.forward_mail.arn
}

# SMTP configuration
output "smtp_endpoint" {
  value = module.mail-service.smtp_endpoint
}

output "smtp_username" {
  value = module.mail-service.smtp_username
}

output "smtp_password" {
  value = nonsensitive(module.mail-service.smtp_password)
}
