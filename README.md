# Terraform AWS Mail Service

A terraform module to setup a SES, Lambda and S3 based email forwarding service.
Attachments will be stripped from the emails and store in S3, a download link will be provided in the forwarded emails, this is to get around limitations with SES.

The setup is based on the blog post [Forward Incoming Email to an External Destination](https://aws.amazon.com/blogs/messaging-and-targeting/forward-incoming-email-to-an-external-destination/) by Brent Meyer, and then adapted with inspiration from [aws-lambda-ses-forwarder](https://github.com/arithmetric/aws-lambda-ses-forwarder) by Joe Turgeon and [aws_lambda_ses_forwarder_python3](https://github.com/tedder/aws_lambda_ses_forwarder_python3) by Ted Timmons.

## Manual steps needed

- Click link to verify ownership of email sent by AWS SES
- [Request production access](https://console.aws.amazon.com/support/home#/case/create?issueType=service-limit-increase&limitType=service-code-ses-sending-limits) for SES, as Sandbox only allows verified email addresses.

## Example Usage

```hcl
resource "aws_route53_zone" "example" {
  name = "example.com"
}

module "mail_service" {
  source = "github.com/AzCii/terraform-aws-mail-service"
  
  dns_zone_ids           = [aws_route53_zone.example.zone_id]
  name                   = "uniqueness"
  aws_region             = var.aws_region
  mail_recipient         = "example@gmail.com"
  mail_sender_prefix     = "mail"
  mx_records             = ["10 inbound-smtp.${var.aws_region}.amazonaws.com"]
  mail_from_mx_records   = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]  
  spf_records            = ["v=spf1 include:amazonses.com include:_spf.google.com ~all"]
  dmarc_records          = ["v=DMARC1; p=none;"]
  dkim_records           = true
  smtp_configuration     = true
  lambda_timeout_seconds = 60
}
```

## Argument Reference

The following arguments are supported:

- source - (Required) Source of the module.
- dns_zone_ids - (Required) List of the ID(s) of the DNS zone to setup the service for, the first ID will be regarded as the primary.
- name - (Required) A name that ensures that resources that need to be uniquely named, are unique.
- aws_region - (Required) The AWS region to create the records in.
- mail_recipient - (Required) The email address to forward mail to.
- mail_sender_prefix - (Required) The user part of the email address to use for the sender email.
- mail_alias_addresses - (Optional) List of additional email addresses to validate for mail sending, for each address added, AWS will mail you a varification link you need to clink.
- mx_records - (Optional) The MX records to create.
- mail_from_mx_records - (Optional) The MX records to create.
- spf_records - (Optional) The SPF records to create.
- dmarc_records - (Optional) The DMARC records to create.
- dkim_records - (Optional) If true, create DKIM records, default is set to false.
- smtp_configuration - (Optional) If true, creates IAM credentials for SMTP, default is set to false.
- lambda_timeout_seconds - (Optional) Amount of time your Lambda Function has to run in seconds. Defaults to `120`. See [Limits](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html).

## Attributes Reference

The following attributes are exported:

- mail_bucket_arn - ARN of the S3 bucket.
- mail_lambda_arn - The Amazon Resource Name (ARN) identifying your Lambda Function.
- smtp_endpoint - The endpoint for the SMTP service.
- smtp_username - The username for the SMTP service.
- smtp_password - The password for the SMTP service, can be outputted in user readable format using `nonsensitive(module.mail-service.smtp_password)`.
- smtp_user_arn - ARM of the IAM user created for SMTP permissions, returns null if smtp_configuration is set to false.

## Known Issues and Quirks

- Emails forwarded will be sent with the FROM address of `mail_sender_prefix`@`domain` (mail@example.com in this example) instead of the real sender email address. Replies will still go to the correct original sender email address, as the original email address are set in REPLY-TO.
- The domain name from the first specified DNS zone, will be used as MailSender in Lambda.
- Email forwarding fails if the TO field is empty, for example, when there are only BCC recipients.
