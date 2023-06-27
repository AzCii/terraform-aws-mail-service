# Terraform AWS Mail Service

A terraform module to setup a SES, Lambda and S3 based email forwarding service.

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
  
  dns_zone_id        = aws_route53_zone.example.zone_id
  domain             = example.com
  aws_region         = var.aws_region
  mail_recipient     = "example@gmail.com"
  mail_sender_prefix = "mail"
  mx_records         = ["10 inbound-smtp.${var.aws_region}.amazonaws.com"]
  spf_records        = ["v=spf1 include:amazonses.com include:_spf.google.com ~all"]
  dmarc_records      = ["v=DMARC1; p=none;"]
}
```

## Argument Reference

The following arguments are supported:

- source - (Required) Source of the module.
- dns_zone_id - (Required) The ID of the DNS zone to create the records in.
- domain - (Required) The domain to create the records for.
- aws_region - (Required) The AWS region to create the records in.
- mail_recipient - (Required) The email address to forward mail to.
- mail_sender_prefix - (Required) The user part of the email address to use for the sender email.
- mx_records - (Optional) The MX records to create.
- spf_records - (Optional) The SPF records to create.
- dmarc_records - (Optional) The DMARC records to create.

## Attributes Reference

The following attributes are exported:

- mail_bucket_arn - ARN of the S3 bucket.
- mail_lambda_arn - The Amazon Resource Name (ARN) identifying your Lambda Function.

## Known Issues

- None
