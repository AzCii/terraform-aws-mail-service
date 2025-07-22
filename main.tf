# Setup bucket for storing incoming e-mails
resource "aws_s3_bucket" "mail" {
  bucket = "${var.domain}-mail-service"
}

# Cleanup old files from S3 bucket
resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.mail.id
  rule {
    id     = "delete-old-files"
    status = "Enabled"

    expiration {
      days = 365
    }
  }
}

# Setup bucket policy to allow SES to write to bucket
resource "aws_s3_bucket_policy" "allow_ses" {
  bucket = aws_s3_bucket.mail.id
  policy = templatefile("${path.module}/policies/s3_allow_ses.tftpl", { bucketName = aws_s3_bucket.mail.bucket, awsAccountId = data.aws_caller_identity.current.account_id })
}

# Setup domain identity
resource "aws_ses_domain_identity" "mail" {
  domain = var.domain
}

# Setup DNS verification record for ses domain identity
resource "aws_route53_record" "dns_verification" {
  zone_id = var.dns_zone_id
  name    = "_amazonses.${aws_ses_domain_identity.mail.id}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.mail.verification_token]
}

# Verify domain identity
resource "aws_ses_domain_identity_verification" "domain_verification" {
  domain     = aws_ses_domain_identity.mail.id
  depends_on = [aws_route53_record.dns_verification]
}

# Verify sender email - Verification email can be found in S3 bucket
resource "aws_ses_email_identity" "forwarder" {
  email = "${var.mail_sender_prefix}@${var.domain}"
}

# Verify reciever email - Verification email will be sent to your inbox
resource "aws_ses_email_identity" "receiver" {
  email = var.mail_recipient
}

# Verify optional alias email addresses
resource "aws_ses_email_identity" "alias" {
  count = length(var.mail_alias_addresses)
  email = var.mail_alias_addresses[count.index]
}

# Configure domain mail from
resource "aws_ses_domain_mail_from" "forwarder" {
  domain           = aws_ses_email_identity.forwarder.email
  mail_from_domain = "${var.mail_sender_prefix}.${aws_ses_domain_identity.mail.domain}"
}

resource "aws_iam_role_policy" "allow_ses" {
  name   = "${var.domain}-allow-ses"
  role   = aws_iam_role.ses_role.id
  policy = templatefile("${path.module}/policies/iam_allow_ses.tftpl", { bucketName = aws_s3_bucket.mail.bucket, region = var.aws_region, awsAccountId = data.aws_caller_identity.current.account_id })
}

resource "aws_iam_role" "ses_role" {
  name = "${var.domain}-ses-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_lambda_function" "forward_mail" {
  filename         = data.archive_file.python_lambda_package.output_path
  function_name    = "${replace(title(var.domain), ".", "", )}MailService"
  role             = aws_iam_role.ses_role.arn
  handler          = "${trimsuffix(basename(data.archive_file.python_lambda_package.source_file), ".py")}.lambda_handler"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  runtime          = "python3.11"
  memory_size      = "1024"

  environment {
    variables = {
      MailS3Bucket  = aws_s3_bucket.mail.bucket,
      MailS3Prefix  = "incoming",
      MailS3Archive = "archived",
      MailS3Error   = "failed",
      MailSender    = "${var.mail_sender_prefix}@${var.domain}",
      MailRecipient = var.mail_recipient,
      Region        = var.aws_region
    }
  }
}

# Lambda will try to send the email 3 times, if an error occurs in the code after the mail is sent, you will recieve the same email 3 times.
resource "aws_lambda_function_event_invoke_config" "limit_retry" {
  function_name          = aws_lambda_function.forward_mail.function_name
  maximum_retry_attempts = 2
}

resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${var.domain}-mail-service"
}

resource "aws_ses_receipt_rule" "store_and_send" {
  name          = "${var.domain}-store_and_send"
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
  enabled       = true

  s3_action {
    bucket_name       = aws_s3_bucket.mail.bucket
    object_key_prefix = aws_lambda_function.forward_mail.environment[0].variables.MailS3Prefix
    position          = 1
  }

  lambda_action {
    function_arn    = aws_lambda_function.forward_mail.arn
    invocation_type = "Event"
    position        = 2
  }
}

# Activate rule set
resource "aws_ses_active_receipt_rule_set" "active_rule_set" {
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
}

resource "aws_lambda_permission" "allow_ses" {
  statement_id  = "AllowExecutionFromSes"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forward_mail.function_name
  principal     = "ses.amazonaws.com"
}

resource "aws_route53_record" "mx_record" {
  count   = length(var.mx_records) > 0 ? 1 : 0
  zone_id = var.dns_zone_id
  name    = var.domain
  type    = "MX"
  ttl     = "600"
  records = var.mx_records
}

resource "aws_route53_record" "domain_mail_from_mx_record" {
  count   = length(var.mail_from_mx_records) > 0 ? 1 : 0
  zone_id = var.dns_zone_id
  name    = aws_ses_domain_mail_from.forwarder.mail_from_domain
  type    = "MX"
  ttl     = "600"
  records = var.mail_from_mx_records
}

resource "aws_route53_record" "spf_record" {
  count   = length(var.spf_records) > 0 ? 1 : 0
  zone_id = var.dns_zone_id
  name    = var.domain
  type    = "TXT"
  records = var.spf_records
  ttl     = "600"
}

resource "aws_route53_record" "domain_mail_from_spf_record" {
  count   = length(var.spf_records) > 0 ? 1 : 0
  zone_id = var.dns_zone_id
  name    = aws_ses_domain_mail_from.forwarder.mail_from_domain
  type    = "TXT"
  ttl     = "600"
  records = var.spf_records
}

resource "aws_route53_record" "dmarc_record" {
  count   = length(var.dmarc_records) > 0 ? 1 : 0
  zone_id = var.dns_zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  records = var.dmarc_records
  ttl     = "600"
}

resource "aws_ses_domain_dkim" "domain_dkim" {
  count  = var.dkim_records ? 1 : 0
  domain = aws_ses_domain_identity.mail.domain
}

resource "aws_route53_record" "dkim_record" {
  count   = var.dkim_records ? 3 : 0
  zone_id = var.dns_zone_id
  name    = "${aws_ses_domain_dkim.domain_dkim[0].dkim_tokens[count.index]}._domainkey"
  type    = "CNAME"
  records = ["${aws_ses_domain_dkim.domain_dkim[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
  ttl     = "600"
}

# SMTP Configuration
# Provides an IAM access key. This is a set of credentials that allow API requests to be made as an IAM user.
resource "aws_iam_user" "user" {
  count = var.smtp_configuration ? 1 : 0
  name  = "${var.domain}_smtp_user"
}

# Provides an IAM access key. This is a set of credentials that allow API requests to be made as an IAM user.
resource "aws_iam_access_key" "access_key" {
  count = var.smtp_configuration ? 1 : 0
  user  = aws_iam_user.user[0].name
}

# Provides an IAM policy attached to a user.
resource "aws_iam_policy" "policy" {
  count  = var.smtp_configuration ? 1 : 0
  name   = "${var.domain}_smtp_userpolicy"
  policy = data.aws_iam_policy_document.policy_document.json
}

# Attaches a Managed IAM Policy to an IAM user
resource "aws_iam_user_policy_attachment" "user_policy" {
  count      = var.smtp_configuration ? 1 : 0
  user       = aws_iam_user.user[0].name
  policy_arn = aws_iam_policy.policy[0].arn
}
