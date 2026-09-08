// ============================================================================
// KAMAI+ SECURE RAZORPAY WEBHOOK BACKEND (Next.js Pages Router / Express)
// File location in Next.js: pages/api/razorpay.js
// Deployable to: Vercel / Node.js
// ============================================================================

import crypto from 'crypto';
import * as admin from 'firebase-admin';

// Disable Next.js body parser to preserve raw buffer for HMAC verification
export const config = {
  api: {
    bodyParser: false,
  },
};

// Helper to buffer the incoming request stream
async function getRawBody(readable) {
  const chunks = [];
  for await (const chunk of readable) {
    chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID || 'kamaiplus',
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const rawBodyBuffer = await getRawBody(req);
    const signature = req.headers['x-razorpay-signature'];
    const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET || 'bhs9g8FV7KjDV7xlqTcDOVcp';

    if (!signature) {
      return res.status(400).json({ error: 'Missing Razorpay signature' });
    }

    const expectedSignature = crypto
      .createHmac('sha256', webhookSecret)
      .update(rawBodyBuffer)
      .digest('hex');

    const isAuthentic = crypto.timingSafeEqual(
      Buffer.from(expectedSignature, 'utf-8'),
      Buffer.from(signature, 'utf-8')
    );

    if (!isAuthentic) {
      console.error('[SECURITY ALERT] Unauthorized Razorpay Webhook attempt.');
      return res.status(401).json({ error: 'Invalid signature' });
    }

    const event = JSON.parse(rawBodyBuffer.toString('utf-8'));

    if (event.event === 'payment.captured' || event.event === 'order.paid') {
      const payment = event.payload.payment.entity;
      const paymentId = payment.id;
      const amountPaise = payment.amount;
      const notes = payment.notes || {};

      const businessId = notes.business_id || notes.businessId || 'biz_starter_pos';
      const plan = notes.plan || (amountPaise >= 140000 ? 'annual' : 'monthly');
      const isAnnual = plan === 'annual';
      const expiryDays = isAnnual ? 365 : 30;

      const now = new Date();
      const expiryDate = new Date(now.getTime() + expiryDays * 24 * 60 * 60 * 1000);

      const db = admin.firestore();
      await db.collection('businesses').doc(businessId).set({
        is_pro: true,
        pro_plan: plan,
        pro_expiry: expiryDate.toISOString(),
        razorpay_payment_id: paymentId,
        pro_amount_paise: amountPaise,
        pro_activated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      return res.status(200).json({ success: true, businessId, paymentId });
    }

    return res.status(200).json({ received: true });
  } catch (error) {
    console.error('[Razorpay Webhook Error]', error);
    return res.status(500).json({ error: error.message || 'Internal error' });
  }
}
