// ============================================================================
// KAMAI+ SECURE RAZORPAY WEBHOOK BACKEND (Next.js App Router)
// File location in Next.js: app/api/razorpay/webhook/route.ts
// Deployable to: Vercel / Cloud Functions / Next.js Serverless
// ============================================================================

import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID || 'kamaiplus',
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

export async function POST(req: NextRequest) {
  try {
    // 1. Read Raw Body as Text (Crucial for cryptographic HMAC verification)
    const rawBody = await req.text();
    const signature = req.headers.get('x-razorpay-signature');
    const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;

    if (!webhookSecret) {
      console.error('RAZORPAY_WEBHOOK_SECRET environment variable is not configured');
      return NextResponse.json({ error: 'Server configuration error' }, { status: 500 });
    }

    if (!signature) {
      return NextResponse.json({ error: 'Missing Razorpay signature' }, { status: 400 });
    }

    // 2. Cryptographic HMAC SHA-256 Verification
    const expectedSignature = crypto
      .createHmac('sha256', webhookSecret)
      .update(rawBody)
      .digest('hex');

    const isAuthentic = crypto.timingSafeEqual(
      Buffer.from(expectedSignature, 'utf-8'),
      Buffer.from(signature, 'utf-8')
    );

    if (!isAuthentic) {
      console.error('[SECURITY ALERT] Unauthorized Razorpay Webhook attempt detected.');
      return NextResponse.json({ error: 'Invalid HMAC signature' }, { status: 401 });
    }

    // 3. Parse Verified Event Payload
    const event = JSON.parse(rawBody);
    console.log(`[Razorpay Webhook Verified] Event: ${event.event}`);

    // 4. Handle Payment Success Events
    if (event.event === 'payment.captured' || event.event === 'order.paid') {
      const payment = event.payload.payment.entity;
      const paymentId = payment.id;
      const amountPaise = payment.amount; // In integer paise (e.g. 149900)
      const notes = payment.notes || {};

      // Identify Business & Plan from verified notes
      const businessId = notes.business_id || notes.businessId || 'biz_starter_pos';
      const plan = notes.plan || (amountPaise >= 140000 ? 'annual' : 'monthly');
      const isAnnual = plan === 'annual';
      const expiryDays = isAnnual ? 365 : 30;

      const now = new Date();
      const expiryDate = new Date(now.getTime() + expiryDays * 24 * 60 * 60 * 1000);

      // 5. Securely Activate Pro Status in Cloud Firestore
      const db = admin.firestore();
      await db.collection('businesses').doc(businessId).set({
        is_pro: true,
        pro_plan: plan,
        pro_expiry: expiryDate.toISOString(),
        razorpay_payment_id: paymentId,
        pro_amount_paise: amountPaise,
        pro_activated_at: admin.firestore.FieldValue.serverTimestamp(),
        last_payment_status: 'captured',
      }, { merge: true });

      console.log(`[PRO ACTIVATED] Business: ${businessId}, Plan: ${plan}, Payment: ${paymentId}`);

      return NextResponse.json({
        success: true,
        message: 'Kamai+ Pro successfully verified and activated',
        businessId,
        paymentId,
      });
    }

    return NextResponse.json({ received: true });
  } catch (error: any) {
    console.error('[Razorpay Webhook Exception]', error);
    return NextResponse.json({ error: error.message || 'Internal error' }, { status: 500 });
  }
}
