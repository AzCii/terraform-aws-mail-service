# Setup bucket for storing incoming e-mails
resource "aws_s3_bucket" "mail" {
  bucket = "${var.name}-mail-service"
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
  for_each = data.aws_route53_zone.zones
  domain   = each.value.name
}


# Setup DNS verification record for ses domain identity
resource "aws_route53_record" "dns_verification" {
  for_each = aws_ses_domain_identity.mail
  zone_id  = each.key
  name     = "_amazonses.${each.value.domain}"
  type     = "TXT"
  ttl      = 600
  records  = [each.value.verification_token]
}


# Verify domain identity
resource "aws_ses_domain_identity_verification" "domain_verification" {
  for_each   = aws_ses_domain_identity.mail
  domain     = each.value.domain
  depends_on = [aws_route53_record.dns_verification]
}


# Verify sender email - Verification email can be found in S3 bucket
resource "aws_ses_email_identity" "forwarder" {
  for_each = aws_ses_domain_identity.mail
  email    = "${var.mail_sender_prefix}@${each.value.domain}"
}

# Verify bounce email - Verification email can be found in S3 bucket
resource "aws_ses_email_identity" "bounce" {
  email = "bounce@${values(data.aws_route53_zone.zones)[0].name}"
}

# Verify reciever email - Verification email will be sent to your inbox
resource "aws_ses_email_identity" "receiver" {
  email = var.mail_recipient
}


# Verify optional alias email addresses
resource "aws_ses_email_identity" "alias" {
  for_each = toset(var.mail_alias_addresses)
  email    = each.key
}


# Configure domain mail from
resource "aws_ses_domain_mail_from" "forwarder" {
  for_each         = aws_ses_domain_identity.mail
  domain           = each.value.domain
  mail_from_domain = "${var.mail_sender_prefix}.${each.value.domain}"
}

resource "aws_iam_role_policy" "allow_ses" {
  name   = "${var.name}-mail-service-allow-ses"
  role   = aws_iam_role.ses_role.id
  policy = templatefile("${path.module}/policies/iam_allow_ses.tftpl", { bucketName = aws_s3_bucket.mail.bucket, region = var.aws_region, awsAccountId = data.aws_caller_identity.current.account_id })
}

resource "aws_iam_role" "ses_role" {
  name = "${var.name}-mail-service-ses-role"

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
  function_name    = "${title(var.name)}MailService"
  role             = aws_iam_role.ses_role.arn
  handler          = "${trimsuffix(basename(data.archive_file.python_lambda_package.source_file), ".py")}.lambda_handler"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  runtime          = "python3.11"
  memory_size      = "1024"

  environment {
    variables = {
      MailS3Bucket    = aws_s3_bucket.mail.bucket,
      MailS3Prefix    = "incoming",
      MailS3Archive   = "archived",
      MailS3Error     = "failed",
      MailSender      = "${var.mail_sender_prefix}@${values(data.aws_route53_zone.zones)[0].name}",
      MailRecipient   = var.mail_recipient,
      IncludeMetadata = var.include_metadata,
      Region          = var.aws_region
    }
  }
}


# Lambda will try to send the email 3 times, if an error occurs in the code after the mail is sent, you will recieve the same email 3 times.
resource "aws_lambda_function_event_invoke_config" "limit_retry" {
  function_name          = aws_lambda_function.forward_mail.function_name
  maximum_retry_attempts = 2
}

resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${var.name}-mail-service"
}

resource "aws_ses_receipt_rule" "bounce" {
  name          = "${var.name}-bounce"
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
  enabled       = true
  recipients    = length(var.bounce_mails_to) > 0 ? var.bounce_mails_to : ["bounce-filter@was-not.configured"] # Filter for the specific email address

  # This action rejects the email
  bounce_action {
    position        = 1
    message         = "The email address you sent to is not valid."
    sender          = aws_ses_email_identity.bounce.email # The address that is "bouncing" the mail
    smtp_reply_code = "550"                               # Mailbox unavailable
    status_code     = "5.1.1"                             # Bad destination mailbox address
  }

  stop_action {
    position = 2
    scope    = "RuleSet"
  }
}

resource "aws_ses_receipt_rule" "store_and_send" {
  name          = "${var.name}-store_and_send"
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
  enabled       = true
  after         = aws_ses_receipt_rule.bounce.name

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
  for_each = {
    for zone_id, zone in data.aws_route53_zone.zones :
    zone_id => zone if length(var.mx_records) > 0
  }
  zone_id = each.key
  name    = each.value.name
  type    = "MX"
  ttl     = 600
  records = var.mx_records
}

resource "aws_route53_record" "domain_mail_from_mx_record" {
  for_each = {
    for zone_id, zone in data.aws_route53_zone.zones :
    zone_id => zone if length(var.mail_from_mx_records) > 0
  }
  zone_id = each.key
  name    = "${var.mail_sender_prefix}.${each.value.name}"
  type    = "MX"
  ttl     = 600
  records = var.mail_from_mx_records
}

resource "aws_route53_record" "spf_record" {
  for_each = {
    for zone_id, zone in data.aws_route53_zone.zones :
    zone_id => zone if length(var.spf_records) > 0
  }
  zone_id = each.key
  name    = each.value.name
  type    = "TXT"
  ttl     = 600
  records = var.spf_records
}

resource "aws_route53_record" "domain_mail_from_spf_record" {
  for_each = {
    for zone_id, zone in data.aws_route53_zone.zones :
    zone_id => zone if length(var.spf_records) > 0
  }
  zone_id = each.key
  name    = "${var.mail_sender_prefix}.${each.value.name}"
  type    = "TXT"
  ttl     = 600
  records = var.spf_records
}

resource "aws_route53_record" "bounce_spf_record" {
  zone_id = values(data.aws_route53_zone.zones)[0].zone_id
  name    = "bounce.${values(data.aws_route53_zone.zones)[0].name}"
  type    = "TXT"
  ttl     = 600
  records = var.spf_records
}

resource "aws_route53_record" "dmarc_record" {
  for_each = {
    for zone_id, zone in data.aws_route53_zone.zones :
    zone_id => zone if length(var.dmarc_records) > 0
  }
  zone_id = each.key
  name    = "_dmarc.${each.value.name}"
  type    = "TXT"
  ttl     = 600
  records = var.dmarc_records
}


# Provides an SES DomainKeys Identified Mail for validation
resource "aws_ses_domain_dkim" "domain_dkim" {
  for_each = {
    for zone_id, domain in aws_ses_domain_identity.mail :
    zone_id => domain if var.dkim_records
  }
  domain = each.value.domain
}

locals {
  zone_domains = {
    for z in values(data.aws_route53_zone.zones) :
    z.zone_id => z.name
  }
}
resource "aws_route53_record" "dkim_record" {
  count = var.dkim_records ? 3 * length(keys(aws_ses_domain_dkim.domain_dkim)) : 0

  zone_id = element(keys(local.zone_domains), floor(count.index / 3))

  name = "${element(
    values(aws_ses_domain_dkim.domain_dkim)[floor(count.index / 3)].dkim_tokens,
    count.index % 3
  )}._domainkey"

  type = "CNAME"
  ttl  = 600
  records = ["${element(
    values(aws_ses_domain_dkim.domain_dkim)[floor(count.index / 3)].dkim_tokens,
    count.index % 3
  )}.dkim.amazonses.com"]
}


# SMTP Configuration
# Provides an IAM access key. This is a set of credentials that allow API requests to be made as an IAM user.
resource "aws_iam_user" "user" {
  count = var.smtp_configuration ? 1 : 0
  name  = "${var.name}_smtp_user"
}


# Provides an IAM access key. This is a set of credentials that allow API requests to be made as an IAM user.
resource "aws_iam_access_key" "access_key" {
  count = var.smtp_configuration ? 1 : 0
  user  = aws_iam_user.user[0].name
}


# Provides an IAM policy attached to a user.
resource "aws_iam_policy" "policy" {
  count  = var.smtp_configuration ? 1 : 0
  name   = "${var.name}_smtp_userpolicy"
  policy = data.aws_iam_policy_document.policy_document.json
}


# Attaches a Managed IAM Policy to an IAM user
resource "aws_iam_user_policy_attachment" "user_policy" {
  count      = var.smtp_configuration ? 1 : 0
  user       = aws_iam_user.user[0].name
  policy_arn = aws_iam_policy.policy[0].arn
}