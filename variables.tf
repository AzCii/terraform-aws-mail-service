variable "domain" {
  description = "The fully qualified domain name"
}

variable "dns_zone_id" {
  description = "Id of the Route53 zone of the fully qualified domain name"
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

variable "mx_records" {
  description = "List of MX records to set for the domain"
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
