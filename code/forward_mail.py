import email
import os
import re
import boto3
from botocore.exceptions import ClientError

# Read the environment variables
mail_recipient = os.environ['MailRecipient']  # An email that is verified by SES to forward the email to.
mail_sender = os.environ['MailSender']  # An email that is verified by SES to use as From address.
incoming_email_bucket = os.environ['MailS3Bucket']  # S3 bucket where SES stores incoming emails.
incoming_email_prefix = os.environ['MailS3Prefix'] # Folder of the incoming emails
archive_email_prefix = os.environ['MailS3Archive'] # Successfully sent emails will be moved to this folder
error_email_prefix = os.environ['MailS3Error'] # Failed emails will be moved to this folder


# Archive the message after email have been sent
def move_email(s3, message_id, destination_folder):
    copy_source = {
        'Bucket': incoming_email_bucket,
        'Key': incoming_email_prefix + "/" + message_id
    }
    try:
        s3.copy_object(Bucket=incoming_email_bucket, Key=destination_folder + "/" + message_id + ".eml", CopySource=copy_source)
        s3.delete_object(Bucket=incoming_email_bucket, Key=incoming_email_prefix + "/" + message_id)
    except ClientError as e: 
        output = e.response['Error']['Message']
    else:
        output = "Message ID " +  message_id + " have been moved to " + destination_folder
    return output

# Send the email
def send_email(message, original_from):

    # Create a new SES resource.
    ses = boto3.client('ses')

    # Try to send the email and return the result.
    try:
        o = ses.send_raw_email(Destinations=[mail_recipient], RawMessage=dict(Data=message))
    except ClientError as e: 
        output = e.response['Error']['Message']
        return False, output 
    else:
        output = "Email from " +  original_from + " was forwarded to " + mail_recipient + " by " + mail_sender
        return True, output

# Lambda handler
def lambda_handler(event, context):

    # Create a new S3 resource
    s3 = boto3.client('s3')

    # Get the message id
    message_id = event['Records'][0]['ses']['mail']['messageId']
    print(f"Received message ID {message_id}")

    # Retrieve the email from your bucket
    object_path = (incoming_email_prefix + "/" + message_id)
    o = s3.get_object(Bucket=incoming_email_bucket, Key=object_path)
    raw_mail = o['Body'].read()
    msg = email.message_from_bytes(raw_mail)

    # Remove the DKIM-Signature header, as it can cause issues with forwarding
    del msg['DKIM-Signature']

    # Replace the original From address with the authenticated forwarding address
    original_from = msg['From']
    del msg['From']
    msg['From'] = re.sub(r'\<.+?\>', '', original_from) + ' <{}>'.format(mail_sender)
    del msg['Reply-To']
    del msg['Return-Path']
    msg['Reply-To'] = original_from
    msg['Return-Path'] = mail_sender

    # Send the email and handle the result
    print(f"Forwarding mail with message ID {message_id}")
    print(f"Original From: {original_from}")
    print(f"From: {msg['From']}")
    print(f"Reply-To: {msg['Reply-To']}")
    print(f"Return-Path: {msg['Return-Path']}")
    message = msg.as_string()   
    success, result = send_email(message, original_from)
    print(result)
    if success:
        # Archive the message
        result = move_email(s3, message_id, archive_email_prefix)
        print(result)
    else:
        # Capture error message in email body
        fail_msg = email.message.EmailMessage()
        fail_msg.set_content(result)
        fail_msg['Subject'] = 'Failed to forward ' + message_id
        # Email failed to send, move it to the error folder
        result = move_email(s3, message_id, error_email_prefix)
        print(result)
        # Send mail about failed forwarding
        fail_msg['From'] = f"Mail Service <{mail_sender}>"
        fail_msg['To'] = mail_recipient
        message = fail_msg.as_string() 
        result = send_email(message, mail_sender)
        print(result)
