import email
import os
import re
import boto3
from botocore.exceptions import ClientError

# Read the environment variables
mail_recipient = os.environ['MailRecipient']  # An email that is verified by SES to use as From address.
mail_sender = os.environ['MailSender']  # An email that is verified by SES to use as From address.
incoming_email_bucket = os.environ['MailS3Bucket']  # S3 bucket where SES stores incoming emails.
incoming_email_prefix = os.environ['MailS3Prefix'] # optional, if messages aren't stored in root

# Send the email
def send_email(message, original_from):

    # Create a new SES resource.
    ses = boto3.client('ses')

    # Try to send the email and return the result.
    try:
        o = ses.send_raw_email(Destinations=[mail_recipient], RawMessage=dict(Data=message))
    except ClientError as e: 
        output = e.response['Error']['Message']
    else:
        output = "Email from " +  original_from + " was forwarded to " + mail_recipient + " by " + mail_sender
    return output

# Lambda handler
def lambda_handler(event, context):

    # Create a new S3 resource
    s3 = boto3.client('s3')

    # Get the message id
    message_id = event['Records'][0]['ses']['mail']['messageId']
    print(f"Received message ID {message_id}")

    # Retrieve the email from your bucket
    if incoming_email_prefix:
        object_path = (incoming_email_prefix + "/" + message_id)
    else:
        object_path = message_id
    o = s3.get_object(Bucket=incoming_email_bucket, Key=object_path)
    raw_mail = o['Body'].read()
    msg = email.message_from_bytes(raw_mail)

    # Replace the original From address with the authenticated forwarding address
    original_from = msg['From']
    del msg['From']
    msg['From'] = re.sub(r'\<.+?\>', '', original_from).strip() + ' <{}>'.format(mail_sender)
    del msg['Reply-To']
    del msg['Return-Path']
    msg['Reply-To'] = original_from
    msg['Return-Path'] = mail_sender

    # Send the email and print the result.
    message = msg.as_string()
    result = send_email(message, original_from)
    print(result)