# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

from email.mime.text import MIMEText
from subprocess import Popen, PIPE
import logging
import traceback

def send_email(sender_email,receiver_email,msg='Problem in PDF job report'):
  log = logging.getLogger('logger')
  try:
    msg = MIMEText(msg)
    msg["From"] = sender_email
    msg["To"] = receiver_email
    msg["Subject"] = "PDF-Job report"
    p = Popen(["/usr/sbin/sendmail", "-t", "-oi"], stdin=PIPE)
    p.communicate(msg.as_bytes())
    log.info(f"Email sent to {receiver_email}")
  except:
    log.warning(f"Sending email FAILED!\n {traceback.format_exc()}")
