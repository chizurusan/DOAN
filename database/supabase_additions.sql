-- ============================================================
-- ROOMIFY — SUPABASE ADDITIONS
-- Chạy file này sau supabase_schema.sql trong SQL Editor
-- ============================================================

-- ── Grant quyền truy cập cho anon và authenticated roles ──────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO anon, authenticated;

-- ── Tắt RLS cho toàn bộ bảng (MVP – bật lại khi deploy production) ────────
ALTER TABLE users                  DISABLE ROW LEVEL SECURITY;
ALTER TABLE roles                  DISABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles             DISABLE ROW LEVEL SECURITY;
ALTER TABLE permissions            DISABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions       DISABLE ROW LEVEL SECURITY;
ALTER TABLE owner_profiles         DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_categories    DISABLE ROW LEVEL SECURITY;
ALTER TABLE properties             DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_images        DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_videos        DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_amenities     DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_amenity_map   DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_documents     DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_status_logs   DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_views         DISABLE ROW LEVEL SECURITY;
ALTER TABLE favorites              DISABLE ROW LEVEL SECURITY;
ALTER TABLE service_packages       DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_vr_tours      DISABLE ROW LEVEL SECURITY;
ALTER TABLE vr_design_requests     DISABLE ROW LEVEL SECURITY;
ALTER TABLE vr_design_progress     DISABLE ROW LEVEL SECURITY;
ALTER TABLE vr_design_files        DISABLE ROW LEVEL SECURITY;
ALTER TABLE vr_design_assignments  DISABLE ROW LEVEL SECURITY;
ALTER TABLE bookings               DISABLE ROW LEVEL SECURITY;
ALTER TABLE booking_status_logs    DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_reviews       DISABLE ROW LEVEL SECURITY;
ALTER TABLE inquiries              DISABLE ROW LEVEL SECURITY;
ALTER TABLE contact_requests       DISABLE ROW LEVEL SECURITY;
ALTER TABLE admin_reviews          DISABLE ROW LEVEL SECURITY;
ALTER TABLE reports                DISABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs             DISABLE ROW LEVEL SECURITY;
ALTER TABLE property_package_orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE payments               DISABLE ROW LEVEL SECURITY;
ALTER TABLE invoices               DISABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_items          DISABLE ROW LEVEL SECURITY;
ALTER TABLE refunds                DISABLE ROW LEVEL SECURITY;
ALTER TABLE notifications          DISABLE ROW LEVEL SECURITY;
ALTER TABLE search_history         DISABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings        DISABLE ROW LEVEL SECURITY;

-- ── Thêm cột vào bảng users ───────────────────────────────────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS saved_property_ids INTEGER[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS membership_tier TEXT;

-- ── Bảng tin đăng của người dùng (linh hoạt hơn bảng properties) ──────────
CREATE TABLE IF NOT EXISTS user_listings (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    owner_name  TEXT,
    owner_phone TEXT,
    title       TEXT    NOT NULL,
    price       TEXT,
    location    TEXT,
    type        TEXT,
    image_url   TEXT,
    vr_url      TEXT,
    bedrooms    INTEGER,
    area        TEXT,
    floors      TEXT,
    description TEXT,
    status      TEXT    NOT NULL DEFAULT 'pending',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE user_listings DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_user_listings_user_id ON user_listings (user_id);
CREATE INDEX IF NOT EXISTS idx_user_listings_status  ON user_listings (status);
CREATE TRIGGER trg_user_listings_updated_at
    BEFORE UPDATE ON user_listings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Bảng đặt lịch xem nhà của người dùng ─────────────────────────────────
CREATE TABLE IF NOT EXISTS user_bookings (
    id              UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    property_id_raw INTEGER,
    property_title  TEXT,
    contact_name    TEXT  NOT NULL DEFAULT '',
    contact_phone   TEXT  NOT NULL DEFAULT '',
    booking_type    TEXT  NOT NULL DEFAULT 'book',
    schedule        TEXT,
    notes           TEXT,
    status          TEXT  NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE user_bookings DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_user_bookings_user_id ON user_bookings (user_id);

-- ── Chatbot messages ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_bot_messages (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    session_key TEXT    NOT NULL,
    user_id     UUID    REFERENCES users(id) ON DELETE SET NULL,
    text        TEXT    NOT NULL,
    is_user     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE chat_bot_messages DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_chat_bot_messages_session
    ON chat_bot_messages (session_key, created_at);

-- ── Member chat rooms ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS member_chat_rooms (
    id                TEXT PRIMARY KEY,
    participant1_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant2_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant1_name TEXT NOT NULL DEFAULT '',
    participant2_name TEXT NOT NULL DEFAULT '',
    property_title    TEXT,
    last_message      TEXT,
    last_message_at   TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE member_chat_rooms DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_member_chat_rooms_p1
    ON member_chat_rooms (participant1_id);
CREATE INDEX IF NOT EXISTS idx_member_chat_rooms_p2
    ON member_chat_rooms (participant2_id);

-- ── Member chat messages ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS member_chat_messages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id     TEXT NOT NULL REFERENCES member_chat_rooms(id) ON DELETE CASCADE,
    sender_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_name TEXT NOT NULL DEFAULT '',
    text        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE member_chat_messages DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_member_chat_messages_room
    ON member_chat_messages (room_id, created_at);
