output "mail_bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.mail.arn
}

output "mail_lambda_arn" {
  description = "The Amazon Resource Name (ARN) identifying your Lambda Function."
  value       = aws_lambda_function.forward_mail.arn
}
