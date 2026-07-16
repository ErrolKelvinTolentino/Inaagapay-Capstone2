// pages/ai-groq.js
// Groq AI (LLaMA 3) integration for InaAgapay Admin Portal

let GROQ_API_KEY = '';
const GROQ_ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
// Updated to the newest supported Llama model
const GROQ_MODEL = 'llama-3.3-70b-versatile';

// Load API key dynamically from .env file
async function loadApiKey() {
    if (GROQ_API_KEY) return GROQ_API_KEY;
    try {
        let response = await fetch('../.env');
        if (!response.ok) {
            response = await fetch('/.env');
        }
        if (!response.ok) {
            throw new Error('Could not load .env file');
        }
        const text = await response.text();
        const lines = text.split('\n');
        for (const line of lines) {
            const match = line.match(/^\s*GROQ_API_KEY\s*=\s*(.*)\s*$/);
            if (match) {
                GROQ_API_KEY = match[1].replace(/['"\r]/g, '').trim();
                return GROQ_API_KEY;
            }
        }
        throw new Error('GROQ_API_KEY not found in .env');
    } catch (err) {
        console.error('Failed to load API key:', err);
        return '';
    }
}

// --------------------------------------------------
// 1. Core reusable analysis function
// --------------------------------------------------
async function analyzeWithGroq(prompt) {
    try {
        const apiKey = await loadApiKey();
        if (!apiKey) {
            return '⚠️ AI analysis temporarily unavailable: GROQ_API_KEY not configured in .env file.';
        }
        const response = await fetch(GROQ_ENDPOINT, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${apiKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: GROQ_MODEL,
                messages: [
                    { role: 'system', content: 'You are an expert healthcare assistant for a maternal and child health information system. Provide concise, actionable, and professional insights.' },
                    { role: 'user', content: prompt }
                ],
                temperature: 0.3,
                max_tokens: 800
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Groq API error (${response.status}): ${errorText}`);
        }

        const data = await response.json();
        return data.choices[0].message.content;
    } catch (err) {
        console.error('Groq analysis failed:', err);
        return `⚠️ AI analysis temporarily unavailable: ${err.message}`;
    }
}

// --------------------------------------------------
// 2. Reusable analysis functions
// --------------------------------------------------
async function analyzeActivity(logs) {
    if (!logs || logs.length === 0) {
        return 'No activity logs to analyze.';
    }

    const prompt = `You are a healthcare system auditor assistant. Use SIMPLE, NON-TECHNICAL language that non-technical users can understand easily.

Analyze the following activity logs from a maternal health system. Provide a clear, easy-to-understand report with these sections:

1. **What's happening** - Describe what users are doing in simple terms
2. **Anything suspicious** - List any unusual patterns, repeated problems, or odd activities in plain language
3. **Important changes** - Mention any significant data changes in simple terms
4. **What we should do** - Give simple recommendations

Use short sentences. Avoid technical jargon. Explain everything like you're talking to someone not familiar with systems.

Logs (most recent first):
${JSON.stringify(logs.slice(0, 100), null, 2)}`;

    return await analyzeWithGroq(prompt);
}

async function analyzePatient(patientData) {
    // Extract mother object and pre‑computed age (if available)
    const mother = patientData.mother || {};
    // age_years is computed in patient-records.html using computeAge()
    const age = mother.age_years !== undefined && mother.age_years !== null 
        ? `${mother.age_years} years old` 
        : 'age not specified';

    const prompt = `You are a healthcare assistant. Use SIMPLE, CLEAR language that anyone can understand.

Analyze this mother's information and explain in plain English:

1. **Overall health** - Describe her current health and pregnancy in simple terms.
2. **Things to watch out for** - List any health concerns based on her records in plain language.
3. **What to do next** - Give simple recommendations for her care.

Important: The mother's age is ${age}. Use this exact age in your analysis. Do NOT recalculate from birthdate. If the mother has multiple pregnancies, focus on the most recent one.

Patient Data:
${JSON.stringify(patientData, null, 2)}`;

    return await analyzeWithGroq(prompt);
}

async function analyzeSystem(stats) {
    const prompt = `You are a system assistant. Use SIMPLE, EASY-TO-UNDERSTAND language.

Look at these numbers and explain in plain English:

1. **What's growing** - Describe the activity and growth trends simply
2. **Numbers that matter** - Point out important or concerning numbers in plain language
3. **What we should do** - Give simple suggestions for improvement

Use everyday language. No technical terms. Make it easy for anyone to understand.

System Stats:
${JSON.stringify(stats, null, 2)}`;

    return await analyzeWithGroq(prompt);
}

async function analyzeRisk(data) {
    const prompt = `You are a security assistant. Use SIMPLE, CLEAR language that anyone can understand.

Analyze this data for anything suspicious or concerning in plain English:

- User actions and activities
- Account changes
- Login problems

Tell us in simple terms:
1. **What suspicious activity do you see?** - List anything that looks wrong or unusual
2. **What unusual patterns are happening?** - Describe any odd activity in plain language
3. **What risky actions are happening?** - Point out dangerous activities
4. **What should we do about it?** - Give simple recommendations

Avoid technical jargon. Explain like you're warning a friend about something.

Data:
${JSON.stringify(data, null, 2)}`;

    return await analyzeWithGroq(prompt);
}

// Helper to display AI result in the existing detail-modal
function showAIAnalysis(title, content) {
    const modal = document.getElementById('detail-modal');
    const body = document.getElementById('detail-body');
    if (!modal || !body) {
        console.error('Detail modal not found on this page');
        alert(title + '\n\n' + content);
        return;
    }

    // Format content with better structure: convert ** bold ** and numbered lists
    let formatted = content
        .replace(/\*\*(.*?)\*\*/g, '<strong style="color: var(--brand-primary);">$1</strong>')
        .replace(/^(\d+\.\s+)/gm, '<div style="margin: 12px 0 0 0;"><span style="font-weight: 600; color: var(--brand-primary);">$1</span>')
        .split('\n')
        .map(line => {
            if (line.trim() === '') return '';
            if (line.match(/^\d+\./)) return line + '</div>';
            return '<span style="display: block; margin: 6px 0;">' + line + '</span>';
        })
        .join('');

    body.innerHTML = `
        <div style="background: var(--bg-secondary); border-radius: var(--radius-card); padding: 24px; border: 1.5px solid var(--border-primary); max-height: 70vh; overflow-y: auto;">
            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 18px; padding-bottom: 12px; border-bottom: 2px solid var(--border-primary);">
                <span style="font-size: 20px;">🤖</span>
                <h3 style="color: var(--brand-primary); margin: 0; font-size: 18px; font-weight: 700;">${title}</h3>
            </div>
            <div style="line-height: 1.8; font-size: 14px; color: var(--text-primary); letter-spacing: 0.3px;">
                ${formatted}
            </div>
        </div>
    `;
    modal.classList.add('show');
}

// Expose globally
window.analyzeWithGroq = analyzeWithGroq;
window.analyzeActivity = analyzeActivity;
window.analyzePatient = analyzePatient;
window.analyzeSystem = analyzeSystem;
window.analyzeRisk = analyzeRisk;
window.showAIAnalysis = showAIAnalysis;