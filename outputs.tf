# Mail bucket ARN
output "mail_bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.mail.arn
}

# Lambda function ARN
output "mail_lambda_arn" {
  description = "The Amazon Resource Name (ARN) identifying your Lambda Function."
  value       = aws_lambda_function.forward_mail.arn
}

# SMTP configuration
output "smtp_endpoint" {
  value = "email-smtp.${var.aws_region}.amazonaws.com"
}

output "smtp_username" {
  value = aws_iam_access_key.access_key[0].id
}

output "smtp_password" {
  value     = aws_iam_access_key.access_key[0].ses_smtp_password_v4
  sensitive = true
}

# SMTP IAM User ARN
output "smtp_user_arn" {
  value = one(aws_iam_user.user[*].arn)
}