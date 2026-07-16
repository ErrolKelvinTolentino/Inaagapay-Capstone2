import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { encode as base64url } from 'https://deno.land/std@0.168.0/encoding/base64url.ts'

// FCM v1 API — uses service account JWT auth (no Legacy server key needed)
const FCM_PROJECT_ID = 'inaagapay'
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

// Semaphore SMS Gateway Configuration
const SEMAPHORE_API_KEY = Deno.env.get('SEMAPHORE_API_KEY') || ''
const SEMAPHORE_SENDER_NAME = Deno.env.get('SEMAPHORE_SENDER_NAME') || 'SEMAPHORE'
const SEMAPHORE_BASE_URL = Deno.env.get('SEMAPHORE_BASE_URL') || 'https://api.semaphore.co/api/v4'

// Service account credentials (embedded from service-account.json)
const SERVICE_ACCOUNT = {
  client_email: 'firebase-adminsdk-fbsvc@inaagapay.iam.gserviceaccount.com',
  private_key: Deno.env.get('FCM_PRIVATE_KEY') || '',
  token_uri: 'https://oauth2.googleapis.com/token',
}

// ── JWT & OAuth2 helpers ────────────────────────────────────────────

async function createJwt(): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' }
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: SERVICE_ACCOUNT.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: SERVICE_ACCOUNT.token_uri,
    iat: now,
    exp: now + 3600,
  }

  const encodedHeader = base64url(new TextEncoder().encode(JSON.stringify(header)))
  const encodedPayload = base64url(new TextEncoder().encode(JSON.stringify(payload)))
  const signingInput = `${encodedHeader}.${encodedPayload}`

  // Import the private key for signing
  // Handle both real newlines and escaped \n from env secrets
  const rawKey = SERVICE_ACCOUNT.private_key.replace(/\\n/g, '\n')
  const pemContents = rawKey
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')
    .replace(/\r/g, '')
    .trim()

  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  )

  const encodedSignature = base64url(new Uint8Array(signature))
  return `${signingInput}.${encodedSignature}`
}

async function getAccessToken(): Promise<string> {
  const jwt = await createJwt()

  const response = await fetch(SERVICE_ACCOUNT.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const data = await response.json()
  if (!data.access_token) {
    throw new Error(`OAuth2 token error: ${JSON.stringify(data)}`)
  }
  return data.access_token
}

// ── Main handler ────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    })
  }

  try {
    const { account_id, title, message, type } = await req.json()

    if (!account_id || !title || !message) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required fields' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    // 1. Try sending FCM Push Notification
    let pushSentCount = 0
    let pushErrorMsg = null
    try {
      if (SERVICE_ACCOUNT.private_key && SERVICE_ACCOUNT.private_key.trim() !== '') {
        // Get active FCM tokens for this account
        const { data: tokens, error } = await supabase
          .from('device_tokens')
          .select('fcm_token, platform')
          .eq('account_id', account_id)
          .eq('is_active', true)

        if (error) {
          console.error(`Database error fetching tokens: ${error.message}`)
          pushErrorMsg = error.message
        } else if (tokens && tokens.length > 0) {
          // Get OAuth2 access token via service account
          const accessToken = await getAccessToken()

          const channelId = type === 'checkup_reminder' ? 'checkup_reminders'
            : type === 'vaccine_reminder' ? 'vaccine_reminders'
            : 'general'

          const failedTokens: string[] = []

          // Send to each device token via FCM v1 API
          for (const { fcm_token } of tokens) {
            try {
              const fcmResponse = await fetch(
                `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
                {
                  method: 'POST',
                  headers: {
                    'Authorization': `Bearer ${accessToken}`,
                    'Content-Type': 'application/json',
                  },
                  body: JSON.stringify({
                    message: {
                      token: fcm_token,
                      notification: {
                        title: title,
                        body: message,
                      },
                      android: {
                        priority: 'HIGH',
                        notification: {
                          sound: 'default',
                          channel_id: channelId,
                          click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        },
                      },
                      data: {
                        type: type || 'general',
                        account_id: String(account_id),
                      },
                    },
                  }),
                }
              )

              if (fcmResponse.ok) {
                pushSentCount++
              } else {
                const errBody = await fcmResponse.json()
                const errCode = errBody?.error?.details?.[0]?.errorCode || errBody?.error?.status || ''
                console.error(`FCM error for token ${fcm_token.substring(0, 20)}...: ${JSON.stringify(errBody?.error?.message || errCode)}`)

                if (errCode === 'UNREGISTERED' || errCode === 'INVALID_ARGUMENT') {
                  failedTokens.push(fcm_token)
                }
              }
            } catch (err: any) {
              console.error(`FCM send error: ${err.message}`)
            }
          }

          // Deactivate invalid tokens
          if (failedTokens.length > 0) {
            await supabase
              .from('device_tokens')
              .update({ is_active: false })
              .in('fcm_token', failedTokens)
            console.log(`Deactivated ${failedTokens.length} invalid tokens`)
          }
          console.log(`Push sent: ${pushSentCount}/${tokens.length} for account ${account_id}`)
        } else {
          console.log(`No active tokens for account ${account_id}`)
        }
      } else {
        console.log('Skipping FCM push: FCM_PRIVATE_KEY is not set')
      }
    } catch (err: any) {
      console.error(`FCM push processing error: ${err.message}`)
      pushErrorMsg = err.message
    }

    // 2. Try sending SMS Reminder via Semaphore if type is vaccine_reminder or checkup_reminder
    let smsSent = false
    let smsErrorMsg = null

    if (type === 'vaccine_reminder' || type === 'checkup_reminder') {
      try {
        // Fetch phone number for this account
        const { data: account, error: accountErr } = await supabase
          .from('accounts')
          .select('phone_number')
          .eq('account_id', account_id)
          .single()

        if (accountErr) {
          console.error(`Database error fetching phone number: ${accountErr.message}`)
          smsErrorMsg = `Failed to retrieve phone number: ${accountErr.message}`
        } else if (account && account.phone_number && account.phone_number.trim() !== '') {
          const rawPhone = account.phone_number.trim()
          
          if (SEMAPHORE_API_KEY && SEMAPHORE_API_KEY.trim() !== '') {
            // Clean and format to Philippine international format
            let formattedNumber = rawPhone.replace(/[^0-9]/g, '')
            if (formattedNumber.startsWith('09')) {
              formattedNumber = '+63' + formattedNumber.substring(1)
            } else if (formattedNumber.startsWith('639')) {
              formattedNumber = '+' + formattedNumber
            } else if (!formattedNumber.startsWith('+') && formattedNumber.startsWith('9')) {
              formattedNumber = '+63' + formattedNumber
            }

            const smsText = `InaAgapay: ${message}`
            console.log(`Sending SMS to ${formattedNumber}...`)

            const params = new URLSearchParams()
            params.append('apikey', SEMAPHORE_API_KEY)
            params.append('number', formattedNumber)
            params.append('message', smsText)
            params.append('sendername', SEMAPHORE_SENDER_NAME)

            const smsResponse = await fetch(`${SEMAPHORE_BASE_URL}/messages`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
              },
              body: params.toString(),
            })

            const resBody = await smsResponse.text()
            if (smsResponse.ok) {
              console.log(`✅ Automated SMS sent successfully: ${resBody}`)
              smsSent = true
            } else {
              console.error(`❌ Semaphore API Error: ${resBody}`)
              smsErrorMsg = `Semaphore Gateway Error: ${resBody}`
            }
          } else {
            console.log('Skipping SMS: SEMAPHORE_API_KEY is not set')
            smsErrorMsg = 'SEMAPHORE_API_KEY is not configured in Supabase secrets'
          }
        } else {
          console.log(`No phone number registered for account ${account_id}`)
          smsErrorMsg = 'No phone number configured on mother account'
        }
      } catch (err: any) {
        console.error(`Automated SMS processing error: ${err.message}`)
        smsErrorMsg = err.message
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        push: { sentCount: pushSentCount, error: pushErrorMsg },
        sms: { sent: smsSent, error: smsErrorMsg }
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }
    )
  } catch (error: any) {
    console.error(`Error: ${error.message}`)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

