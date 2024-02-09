# Data source to get the current AWS account ID
data "aws_caller_identity" "current" {}

# Package the Python Lambda function
data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/code/forward_mail.py"
  output_path = "${path.module}/code/forward_mail.zip"
}

# Attaches a Managed IAM Policy to SES Email Identity resource
data "aws_iam_policy_document" "policy_document" {
  statement {
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = concat([aws_ses_email_identity.forwarder.arn], aws_ses_email_identity.alias[*].arn)
  }
}