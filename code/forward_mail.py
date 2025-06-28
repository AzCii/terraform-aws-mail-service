import email
import os
import re
import boto3
from botocore.exceptions import ClientError
from email.mime.application import MIMEApplication

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
        output = "Message ID " + message_id + " have been moved to " + destination_folder
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
        output = "Email from " + original_from + " was forwarded to " + mail_recipient + " by " + mail_sender
        return True, output


# Save attachments to S3
def save_attachments_to_s3(msg, message_id, s3):
    attachment_prefix = f"attachments/{message_id}"
    s3_links = []

    for part in msg.walk():
        content_disposition = part.get("Content-Disposition", "")
        if part.get_content_maintype() == 'multipart':
            continue
        if "attachment" in content_disposition:
            filename = part.get_filename()
            if not filename:
                continue
            file_data = part.get_payload(decode=True)
            s3_key = f"{attachment_prefix}/{filename}"

            try:
                # Upload file
                s3.put_object(Bucket=incoming_email_bucket, Key=s3_key, Body=file_data)

                # Generate pre-signed URL
                url = s3.generate_presigned_url(
                    ClientMethod='get_object',
                    Params={'Bucket': incoming_email_bucket, 'Key': s3_key},
                    ExpiresIn=7 * 24 * 60 * 60
                )
                s3_links.append((filename, url))
                print(f"Saved {filename} to S3 with URL.")
            except ClientError as e:
                print(f"Error saving attachment {filename}: {e.response['Error']['Message']}")
    return s3_links


# Strip attachments from the email and add links to download them
def strip_attachments_and_add_links(msg, attachment_links):
    from email.message import EmailMessage
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText

    # Create a new multipart/related message (HTML + inline images)
    new_msg = MIMEMultipart("related")
    alternative = MIMEMultipart("alternative")
    new_msg.attach(alternative)

    html_body = ""
    plain_body = ""

    inline_parts = []

    for part in msg.walk():
        content_type = part.get_content_type()
        content_disposition = part.get("Content-Disposition", "")
        content_id = part.get("Content-ID", None)
        charset = part.get_content_charset() or "utf-8"

        if part.get_content_maintype() == 'multipart':
            continue

        if "attachment" in content_disposition:
            # Skip actual attachments
            continue

        elif content_type == "text/html":
            html_body = part.get_payload(decode=True).decode(charset)

        elif content_type == "text/plain" and not plain_body:
            plain_body = part.get_payload(decode=True).decode(charset)

        elif content_id:
            # Preserving inline images
            inline_parts.append(part)

    # Fallback: use plain if no HTML
    if not html_body:
        html_body = "<pre>{}</pre>".format(plain_body.replace("<", "&lt;").replace(">", "&gt;"))

    # Add S3 links to attachments
    if attachment_links:
        links_html = "<br><p><strong>Attachments ready for download from S3:</strong></p><ul>"
        for filename, url in attachment_links:
            links_html += f'<li><a href="{url}">{filename}</a></li>'
        links_html += "</ul>"

        # Try to inject before </body>, else append
        if "</body>" in html_body.lower():
            body_tag = re.search(r"</body>", html_body, re.IGNORECASE)
            insert_pos = body_tag.start()
            html_body = html_body[:insert_pos] + links_html + html_body[insert_pos:]
        else:
            html_body += links_html

    # Attach plain and HTML versions
    alternative.attach(MIMEText(plain_body, 'plain'))
    alternative.attach(MIMEText(html_body, 'html'))

    # Attach preserved inline images
    for part in inline_parts:
        new_msg.attach(part)

    # Copy over headers except those that conflict
    excluded_headers = {
        'content-type',
        'content-transfer-encoding',
        'mime-version',
        'content-disposition'
    }

    for header_key, header_value in msg.items():
        if header_key.lower() not in excluded_headers:
            new_msg[header_key] = header_value.strip().replace('\n', ' ').replace('\r', ' ')

    return new_msg


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

    # Save attachments and get their URLs
    attachment_links = save_attachments_to_s3(msg, message_id, s3)
    print(f"Saved attachments: {attachment_links}")

    # Remove attachments and inject download links
    msg = strip_attachments_and_add_links(msg, attachment_links)

    # Remove the DKIM-Signature header, as it can cause issues with forwarding
    del msg['DKIM-Signature']

    # Replace the original From address with the authenticated forwarding address
    original_from = msg['From']
    del msg['From']
    msg['From'] = re.sub(r'\<.+?\>', '', original_from) + ' <{}>'.format(mail_sender)

    # Set the Reply-To to ensure that reply emails goes back to the original sender
    del msg['Reply-To']
    msg['Reply-To'] = original_from

    # Set the Return-Path to ensure that bounce emails are also forwarded to the authenticated receiver address
    del msg['Return-Path']
    msg['Return-Path'] = mail_recipient

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

        # Create a new MIME object to attach the orginal email
        att = MIMEApplication(raw_mail, message_id + ".eml")
        att.add_header("Content-Disposition", 'attachment', filename=message_id + ".eml")

        # Send mail about failed forwarding
        fail_msg['From'] = f"Mail Service <{mail_sender}>"
        fail_msg['To'] = mail_recipient
        message = fail_msg.as_string() 
        result = send_email(message, mail_sender)
        print(result)