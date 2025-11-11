variable "name" {
  description = "A name that ensures that resources that need to be uniquely named, are unique"
}

variable "dns_zone_ids" {
  description = "List of Ids of the Route53 zones of the fully qualified domain names"
  type        = list(string)
}

variable "aws_region" {
  description = "The AWS region"
}

variable "mail_recipient" {
  description = "The address that you want to forward the message to"
}

variable "mail_sender_prefix" {
  description = "The prefix of the email address that the forwarded message will be sent from"
}

variable "mail_alias_addresses" {
  description = "List of additional email addresses to validate for mail sending"
  type        = list(string)
  default     = []
}

variable "include_metadata" {
  description = "If true, embed the metadata footer (From, To, etc.) in the email."
  type        = bool
  default     = false
}

variable "bounce_mails_to" {
  description = "Optional list of receiving email addresses to block by sending back bounce messages"
  type        = list(string)
  default     = []
}

variable "mx_records" {
  description = "List of MX records to set for the domain"
  type        = list(any)
  default     = []
}

variable "mail_from_mx_records" {
  description = "List of MX records to set for the custom mail from domain"
  type        = list(any)
  default     = []
}

variable "spf_records" {
  description = "List of Sender Policy Framework records to set for the domain"
  type        = list(any)
  default     = []
}

variable "dmarc_records" {
  description = "List of Domain-based Message Authentication, Reporting and Conformance records to set for the domain"
  type        = list(any)
  default     = []
}

variable "dkim_records" {
  description = "Provides an SES DomainKeys Identified Mail resource"
  type        = bool
  default     = false
}

variable "smtp_configuration" {
  description = "Configure credentials for SMTP access"
  type        = bool
  default     = false
}

variable "lambda_timeout_seconds" {
  description = "Amount of time your Lambda Function has to run in seconds"
  type        = number
  default     = 120
}