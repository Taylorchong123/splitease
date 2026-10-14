const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();

/**
 * Triggered when the app queues a payment reminder in `notifications/{id}`.
 * Sends both a Push Notification (FCM) and an Email with the itemized bill breakdown.
 */
exports.sendPaymentNotification = onDocumentCreated('notifications/{id}', async (event) => {
  const n = event.data.data();
  if (!n) return;

  const formattedAmount = (n.amount / 100).toFixed(2);
  const items = n.items || [];

  // Build Itemized HTML Table & Text Summary
  let itemsHtml = '';
  let itemsText = '';

  for (const item of items) {
    const itemShare = (item.pShare / 100).toFixed(2);
    const splitInfo = item.sharedWithCount > 1 ? ` (Split with ${item.sharedWithCount} people)` : '';

    itemsHtml += `
      <tr style="border-bottom: 1px solid #eee;">
        <td style="padding: 10px 0;">
          <strong>${item.name}</strong> (${item.quantity}x)${splitInfo}
        </td>
        <td style="padding: 10px 0; text-align: right; font-weight: 500;">
          ${n.currency} ${itemShare}
        </td>
      </tr>
    `;

    itemsText += `• ${item.name} (${item.quantity}x)${splitInfo}: ${n.currency} ${itemShare}\n`;
  }

  if (n.tax > 0) {
    itemsHtml += `
      <tr style="border-bottom: 1px solid #eee; color: #666;">
        <td style="padding: 8px 0; font-size: 13px;">SST / Tax Share (Proportional)</td>
        <td style="padding: 8px 0; text-align: right; font-size: 13px;">Included in total</td>
      </tr>
    `;
    itemsText += `• SST/Tax: Allocated proportionally\n`;
  }

  if (n.serviceCharge > 0) {
    itemsHtml += `
      <tr style="border-bottom: 1px solid #eee; color: #666;">
        <td style="padding: 8px 0; font-size: 13px;">Service Charge Share (Proportional)</td>
        <td style="padding: 8px 0; text-align: right; font-size: 13px;">Included in total</td>
      </tr>
    `;
    itemsText += `• Service Charge: Allocated proportionally\n`;
  }

  const subject = `Payment Reminder: You owe ${n.currency} ${formattedAmount} for "${n.title || 'Bill'}"`;

  const htmlContent = `
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px; color: #333;">
      <h2 style="color: #02569B; margin-top: 0;">
        💸 SplitEase Bill Breakdown
      </h2>
      <p>Hi <strong>${n.toName || 'there'}</strong>,</p>
      <p><strong>${n.ownerName || 'Your friend'}</strong> sent you a payment reminder for <strong>"${n.title || 'Bill'}"</strong>.</p>

      <div style="background-color: #f8f9fa; padding: 16px; border-radius: 6px; margin: 20px 0;">
        <h3 style="margin-top: 0; color: #444; border-bottom: 2px solid #ddd; padding-bottom: 8px;">
          Your Itemized Share:
        </h3>
        <table style="width: 100%; border-collapse: collapse; margin-bottom: 12px;">
          <tbody>
            ${itemsHtml || `<tr><td style="padding: 8px 0;">Share of bill total</td><td style="text-align: right;">${n.currency} ${formattedAmount}</td></tr>`}
          </tbody>
        </table>

        <div style="background: #e8f5e9; padding: 12px; border-radius: 6px; text-align: right; margin-top: 15px;">
          <span style="font-size: 14px; color: #2e7d32;">Total Owed:</span>
          <br/>
          <strong style="font-size: 22px; color: #1b5e20;">${n.currency} ${formattedAmount}</strong>
        </div>
      </div>

      <p style="color: #666; font-size: 14px;">
        Please make your payment to <strong>${n.ownerName || 'the bill owner'}</strong>
        ${n.ownerEmail ? `(${n.ownerEmail})` : ''}.
      </p>
      <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
      <p style="color: #999; font-size: 12px; text-align: center;">
        Sent via SplitEase · Split bills fairly in any currency
      </p>
    </div>
  `;

  const textContent = `Hi ${n.toName || 'there'},\n\n` +
    `${n.ownerName || 'Your friend'} sent you a payment reminder for "${n.title || 'Bill'}".\n\n` +
    `YOUR ITEMIZED BREAKDOWN:\n` +
    `${itemsText}\n` +
    `TOTAL OWED: ${n.currency} ${formattedAmount}\n\n` +
    `Please pay ${n.ownerName || 'the owner'} (${n.ownerEmail || ''}).\n\n` +
    `Sent via SplitEase`;

  // Read email credentials inside function handler when process.env is populated
  const emailUser = (process.env.EMAIL_USER || '').trim();
  const emailPass = (process.env.EMAIL_PASS || '').replace(/\s+/g, '');
  const emailService = (process.env.EMAIL_SERVICE || 'gmail').trim();

  if (emailUser && emailPass) {
    const mailTransporter = nodemailer.createTransport({
      service: emailService,
      auth: {
        user: emailUser,
        pass: emailPass,
      },
    });

    try {
      const info = await mailTransporter.sendMail({
        from: `"SplitEase" <${emailUser}>`,
        to: n.toEmail,
        subject: subject,
        text: textContent,
        html: htmlContent,
      });
      console.log(`SUCCESS: Email sent to ${n.toEmail}. Message ID: ${info.messageId}`);
    } catch (mailErr) {
      console.error(`ERROR: Failed to send email to ${n.toEmail}:`, mailErr);
    }
  } else {
    console.log(`WARNING: EMAIL_USER or EMAIL_PASS not set. EMAIL_USER="${emailUser}"`);
  }

  // Send Push Notification if FCM token exists for recipient
  try {
    const users = await admin
      .firestore()
      .collection('users')
      .where('email', '==', n.toEmail)
      .limit(1)
      .get();

    if (!users.empty) {
      const tokens = users.docs[0].get('fcmTokens') || [];
      if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: `You owe ${n.currency} ${formattedAmount}`,
            body: `For "${n.title}" · Tap to open SplitEase`,
          },
          data: { ticketId: n.ticketId },
        });
        console.log(`SUCCESS: Push notification sent to ${n.toEmail}`);
      }
    }
  } catch (fcmErr) {
    console.error(`ERROR: Failed to send push notification to ${n.toEmail}:`, fcmErr);
  }
});
