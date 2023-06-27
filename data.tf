data "aws_caller_identity" "current" {}

data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/code/forward_mail.py"
  output_path = "${path.module}/code/forward_mail.zip"
}
