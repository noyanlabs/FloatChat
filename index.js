// src/index.js
import { neon } from '@neondatabase/serverless';

const SCHEMA = `
Table: profiles
Columns (case-sensitive, MUST be double-quoted exactly as shown in SQL, e.g. "TEMP", "PRES"):
  "N_PROF" (bigint), "N_LEVELS" (bigint),
  "TEMP" (real), "PRES" (real), "PSAL" (real),
  "LATITUDE" (double precision), "LONGITUDE" (double precision),
  "JULD" (timestamp without time zone),
  "TEMP_QC" (text), "PRES_QC" (text), "PSAL_QC" (text),
  "TEMP_ADJUSTED" (real), "PRES_ADJUSTED" (real), "PSAL_ADJUSTED" (real)
`;

const MODEL = "claude-sonnet-5";

async function callClaude(messages, apiKey, maxTokens = 500) {
  const resp = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: maxTokens,
      thinking: { type: "disabled" },
      output_config: { effort: "low" },
      messages
    })
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Claude API error ${resp.status}: ${errText}`);
  }

  const data = await resp.json();
  return data.content
    .filter(block => block.type === 'text')
    .map(block => block.text)
    .join('');
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }
    if (request.method !== 'POST') {
      return new Response('Use POST', { status: 405, headers: CORS_HEADERS });
    }

    let question;
    try {
      const body = await request.json();
      question = body.question;
      if (!question || typeof question !== 'string') {
        throw new Error('Missing "question" field');
      }
    } catch (err) {
      return Response.json({ error: 'Invalid request body', detail: err.message }, { status: 400, headers: CORS_HEADERS });
    }

    // env.ANTHROPIC_API_KEY and env.DATABASE_URL come from Worker secrets —
    // set via `npx wrangler secret put ANTHROPIC_API_KEY` and `npx wrangler secret put DATABASE_URL`
    // never hardcode these, never log them, never return them in a response
    if (!env.ANTHROPIC_API_KEY || !env.DATABASE_URL) {
      return Response.json({ error: 'Server misconfigured: missing secrets' }, { status: 500, headers: CORS_HEADERS });
    }

    const sql = neon(env.DATABASE_URL);

    // Step 1: NL -> SQL
    let generatedSQL;
    try {
      const sqlPrompt = `You are a SQL generator for a PostgreSQL database of ARGO ocean float data.

${SCHEMA}

IMPORTANT: All column names are uppercase and MUST be wrapped in double quotes exactly as shown (e.g. "TEMP", not TEMP or temp), or the query will fail. The table name "profiles" is lowercase and does NOT need quotes.

User question: "${question}"

Return ONLY a single valid SQL SELECT query. No explanation, no markdown formatting, no backticks, no semicolon-separated multiple statements.`;
      generatedSQL = (await callClaude(
        [{ role: 'user', content: sqlPrompt }],
        env.ANTHROPIC_API_KEY
      )).trim();

      generatedSQL = generatedSQL.replace(/^```sql\s*/i, '').replace(/```$/, '').trim();
    } catch (err) {
      return Response.json({ error: 'LLM SQL generation failed', detail: err.message }, { status: 502, headers: CORS_HEADERS });
    }

    // Step 2: safety check
    const lowered = generatedSQL.toLowerCase();
    if (!lowered.startsWith('select') || /\b(insert|update|delete|drop|alter|truncate|;)\b/.test(lowered.slice(6))) {
      return Response.json({ error: 'Rejected unsafe or non-SELECT query', raw: generatedSQL }, { status: 400, headers: CORS_HEADERS });
    }

    // Step 3: execute against Neon
    let rows;
    try {
      rows = await sql.query(generatedSQL);
    } catch (err) {
      return Response.json({ error: 'SQL execution failed', detail: err.message, sql: generatedSQL }, { status: 400, headers: CORS_HEADERS });
    }

    // Step 4: result -> natural language
    let answer;
    try {
      const answerPrompt = `User asked: "${question}"

SQL query used: ${generatedSQL}

Result (JSON rows, truncated if long): ${JSON.stringify(rows).slice(0, 3000)}

Give a short, clear natural-language answer to the user's question based on this result.`;

      answer = await callClaude(
        [{ role: 'user', content: answerPrompt }],
        env.ANTHROPIC_API_KEY
      );
    } catch (err) {
      return Response.json({ error: 'LLM answer generation failed', detail: err.message, sql: generatedSQL, rows }, { status: 502, headers: CORS_HEADERS });
    }

    return Response.json(
      { question, sql: generatedSQL, rows, answer },
      { headers: CORS_HEADERS }
    );
  }
};
