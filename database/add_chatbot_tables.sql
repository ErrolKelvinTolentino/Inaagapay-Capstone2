-- Create chatbot sessions table to group conversations
CREATE TABLE IF NOT EXISTS chatbot_sessions (
  session_id BIGSERIAL PRIMARY KEY,
  mother_id BIGINT NOT NULL REFERENCES mothers(mother_id) ON DELETE CASCADE,
  title VARCHAR(255) DEFAULT 'Kausap si Ate Assistant',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create chatbot messages table to store individual chat logs
CREATE TABLE IF NOT EXISTS chatbot_messages (
  message_id BIGSERIAL PRIMARY KEY,
  session_id BIGINT NOT NULL REFERENCES chatbot_sessions(session_id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  is_user BOOLEAN NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_chatbot_sessions_mother ON chatbot_sessions(mother_id);
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_session ON chatbot_messages(session_id);

-- Disable Row-Level Security (RLS) to conform to the rest of the database configuration
ALTER TABLE chatbot_sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE chatbot_messages DISABLE ROW LEVEL SECURITY;
