# Data source to get the current AWS account ID
data "aws_caller_identity" "current" {}


# Package the Python Lambda function
data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/code/forward_mail.py"
  output_path = "${path.module}/code/forward_mail.zip"
}


# Attaches a Managed IAM Policy to SES Email Identity resource
locals {
  all_ses_identities_arns = concat(
    values(aws_ses_email_identity.forwarder)[*].arn,
    values(aws_ses_email_identity.alias)[*].arn
  )
}

data "aws_iam_policy_document" "policy_document" {
  statement {
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = local.all_ses_identities_arns
  }
}


# Data of the dns zones
data "aws_route53_zone" "zones" {
  for_each = toset(var.dns_zone_ids)
  zone_id = each.value
}