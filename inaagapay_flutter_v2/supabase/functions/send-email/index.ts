// import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// const BREVO_API_KEY = Deno.env.get('BREVO_API_KEY') || ''

// serve(async (req) => {
//   if (req.method === 'OPTIONS') {
//     return new Response('ok', {
//       headers: {
//         'Access-Control-Allow-Origin': '*',
//         'Access-Control-Allow-Methods': 'POST, OPTIONS',
//         'Access-Control-Allow-Headers': 'Content-Type, Authorization',
//       },
//     })
//   }

//   try {
//     const { email, code, subject, htmlContent } = await req.json()

//     if (!email || !subject || !htmlContent) {
//       return new Response(
//         JSON.stringify({ success: false, error: 'Missing required fields' }),
//         { status: 400, headers: { 'Content-Type': 'application/json' } }
//       )
//     }

//     console.log(`Sending email to: ${email}`)

//     const response = await fetch('https://api.brevo.com/v3/smtp/email', {
//       method: 'POST',
//       headers: {
//         'api-key': BREVO_API_KEY,
//         'Content-Type': 'application/json',
//       },
//       body: JSON.stringify({
//         sender: {
//           name: 'InaAgapay',
//           email: 'brentbernardo76@gmail.com'  // ← YOUR VERIFIED EMAIL
//         },
//         to: [{ email: email }],
//         subject: subject,
//         htmlContent: htmlContent,
//       }),
//     })

//     const responseData = await response.json()

//     if (response.ok) {
//       console.log(`✅ Email sent successfully`)
//       return new Response(
//         JSON.stringify({ success: true, messageId: responseData.messageId }),
//         { status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }
//       )
//     } else {
//       console.error(`❌ Brevo error: ${JSON.stringify(responseData)}`)
//       return new Response(
//         JSON.stringify({ success: false, error: responseData.message }),
//         { status: 500, headers: { 'Content-Type': 'application/json' } }
//       )
//     }
//   } catch (error) {
//     console.error(`❌ Error: ${error.message}`)
//     return new Response(
//       JSON.stringify({ success: false, error: error.message }),
//       { status: 500, headers: { 'Content-Type': 'application/json' } }
//     )
//   }
// })