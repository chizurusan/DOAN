-- ============================================================
-- ROOMIFY — COMPLETE POSTGRESQL SCHEMA
-- PostgreSQL 15+  |  snake_case  |  UUID PKs  |  Version 1.0
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Auto-update trigger function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE user_status AS ENUM (
    'active',
    'inactive',
    'suspended',
    'pending_verification',
    'banned'
);

CREATE TYPE owner_verification_status AS ENUM (
    'pending',
    'under_review',
    'verified',
    'rejected'
);

CREATE TYPE property_status AS ENUM (
    'draft',
    'pending_approval',
    'active',
    'rejected',
    'inactive',
    'archived',
    'rented',
    'sold'
);

CREATE TYPE booking_status AS ENUM (
    'pending',
    'confirmed',
    'cancelled',
    'completed',
    'no_show'
);

CREATE TYPE inquiry_status AS ENUM (
    'new',
    'read',
    'replied',
    'closed',
    'spam'
);

CREATE TYPE review_decision AS ENUM (
    'pending',
    'approved',
    'rejected',
    'needs_revision'
);

CREATE TYPE report_status AS ENUM (
    'pending',
    'under_review',
    'resolved',
    'dismissed'
);

CREATE TYPE payment_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'refunded',
    'partially_refunded',
    'cancelled',
    'expired'
);

CREATE TYPE payment_type AS ENUM (
    'service_package',
    'vr_design_service',
    'listing_fee',
    'featured_listing',
    'booking_deposit',
    'other'
);

CREATE TYPE invoice_status AS ENUM (
    'draft',
    'issued',
    'paid',
    'overdue',
    'cancelled',
    'void'
);

CREATE TYPE refund_status AS ENUM (
    'requested',
    'approved',
    'processing',
    'completed',
    'rejected',
    'cancelled'
);

CREATE TYPE vr_request_status AS ENUM (
    'pending',
    'assigned',
    'in_progress',
    'under_review',
    'revision_requested',
    'completed',
    'cancelled',
    'rejected'
);

CREATE TYPE vr_progress_status AS ENUM (
    'not_started',
    'in_progress',
    'completed',
    'blocked',
    'cancelled'
);

CREATE TYPE assignment_status AS ENUM (
    'assigned',
    'accepted',
    'in_progress',
    'completed',
    'reassigned',
    'cancelled'
);

CREATE TYPE notification_type AS ENUM (
    'booking_update',
    'inquiry_reply',
    'property_approved',
    'property_rejected',
    'payment_received',
    'payment_failed',
    'vr_update',
    'review_received',
    'report_update',
    'system_alert',
    'general',
    'new_message'
);

CREATE TYPE service_type AS ENUM (
    'listing_basic',
    'listing_featured',
    'listing_premium',
    'vr_basic',
    'vr_advanced',
    'vr_custom',
    'consultation'
);


-- ============================================================
-- AUTH / USER / RBAC
-- ============================================================

CREATE TABLE users (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email               VARCHAR(255) NOT NULL,
    phone               VARCHAR(20),
    password_hash       TEXT        NOT NULL,
    full_name           VARCHAR(255) NOT NULL,
    avatar_url          TEXT,
    status              user_status NOT NULL DEFAULT 'active',
    email_verified_at   TIMESTAMPTZ,
    phone_verified_at   TIMESTAMPTZ,
    last_login_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_phone UNIQUE (phone)
);

CREATE INDEX idx_users_email      ON users (email);
CREATE INDEX idx_users_status     ON users (status);
CREATE INDEX idx_users_active     ON users (id) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE roles (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(50) NOT NULL,
    display_name    VARCHAR(100),
    description     TEXT,
    is_system       BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_roles_name UNIQUE (name)
);

CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE user_roles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role_id     UUID        NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    assigned_by UUID        REFERENCES users (id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ,
    CONSTRAINT uq_user_roles UNIQUE (user_id, role_id)
);

CREATE INDEX idx_user_roles_user_id ON user_roles (user_id);
CREATE INDEX idx_user_roles_role_id ON user_roles (role_id);

-- -------------------------------------------------------

CREATE TABLE permissions (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(100) NOT NULL,
    display_name VARCHAR(150),
    description  TEXT,
    module       VARCHAR(50),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_permissions_name UNIQUE (name)
);

CREATE INDEX idx_permissions_module ON permissions (module);

-- -------------------------------------------------------

CREATE TABLE role_permissions (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id       UUID        NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    permission_id UUID        NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_role_permissions UNIQUE (role_id, permission_id)
);

CREATE INDEX idx_role_permissions_role_id       ON role_permissions (role_id);
CREATE INDEX idx_role_permissions_permission_id ON role_permissions (permission_id);

-- -------------------------------------------------------

CREATE TABLE owner_profiles (
    id                UUID                      PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID                      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    business_name     VARCHAR(255),
    business_type     VARCHAR(50),
    tax_id            VARCHAR(50),
    license_number    VARCHAR(100),
    bio               TEXT,
    website_url       TEXT,
    address           TEXT,
    city              VARCHAR(100),
    province          VARCHAR(100),
    verified_status   owner_verification_status NOT NULL DEFAULT 'pending',
    verified_at       TIMESTAMPTZ,
    verified_by       UUID                      REFERENCES users (id) ON DELETE SET NULL,
    rejection_reason  TEXT,
    total_listings    INTEGER                   NOT NULL DEFAULT 0,
    rating_average    NUMERIC(3,2)              NOT NULL DEFAULT 0.00,
    created_at        TIMESTAMPTZ               NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ               NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_owner_profiles_user_id UNIQUE (user_id)
);

CREATE INDEX idx_owner_profiles_verified_status ON owner_profiles (verified_status);

CREATE TRIGGER trg_owner_profiles_updated_at
    BEFORE UPDATE ON owner_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- PROPERTY MODULE
-- ============================================================

CREATE TABLE property_categories (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id     UUID         REFERENCES property_categories (id) ON DELETE SET NULL,
    name          VARCHAR(100) NOT NULL,
    slug          VARCHAR(120) NOT NULL,
    description   TEXT,
    icon_url      TEXT,
    display_order INTEGER      NOT NULL DEFAULT 0,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_property_categories_slug UNIQUE (slug)
);

CREATE INDEX idx_property_categories_parent_id ON property_categories (parent_id);
CREATE INDEX idx_property_categories_is_active ON property_categories (is_active);

CREATE TRIGGER trg_property_categories_updated_at
    BEFORE UPDATE ON property_categories
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE properties (
    id               UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id         UUID            NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    category_id      UUID            NOT NULL REFERENCES property_categories (id) ON DELETE RESTRICT,
    title            VARCHAR(300)    NOT NULL,
    slug             VARCHAR(350),
    description      TEXT,
    property_type    VARCHAR(50),
    listing_type     VARCHAR(20)     NOT NULL,
    price            NUMERIC(15,2),
    price_unit       VARCHAR(20),
    currency         VARCHAR(3)      NOT NULL DEFAULT 'VND',
    area             NUMERIC(10,2),
    bedrooms         SMALLINT,
    bathrooms        SMALLINT,
    floors           SMALLINT,
    direction        VARCHAR(20),
    legal_status     VARCHAR(100),
    address_line     TEXT,
    ward             VARCHAR(100),
    district         VARCHAR(100),
    city             VARCHAR(100),
    province         VARCHAR(100),
    country          VARCHAR(100)    NOT NULL DEFAULT 'Vietnam',
    latitude         NUMERIC(10,7),
    longitude        NUMERIC(10,7),
    status           property_status NOT NULL DEFAULT 'draft',
    is_featured      BOOLEAN         NOT NULL DEFAULT FALSE,
    is_vr_enabled    BOOLEAN         NOT NULL DEFAULT FALSE,
    featured_until   TIMESTAMPTZ,
    view_count       INTEGER         NOT NULL DEFAULT 0,
    contact_count    INTEGER         NOT NULL DEFAULT 0,
    tags             TEXT[],
    meta_title       VARCHAR(300),
    meta_description TEXT,
    published_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ,
    CONSTRAINT uq_properties_slug      UNIQUE (slug),
    CONSTRAINT chk_properties_listing  CHECK (listing_type IN ('sale','rent','both'))
);

CREATE INDEX idx_properties_owner_id     ON properties (owner_id);
CREATE INDEX idx_properties_category_id  ON properties (category_id);
CREATE INDEX idx_properties_status       ON properties (status);
CREATE INDEX idx_properties_listing_type ON properties (listing_type);
CREATE INDEX idx_properties_city         ON properties (city);
CREATE INDEX idx_properties_province     ON properties (province);
CREATE INDEX idx_properties_price        ON properties (price);
CREATE INDEX idx_properties_featured     ON properties (is_featured, featured_until) WHERE is_featured = TRUE;
CREATE INDEX idx_properties_active       ON properties (status, published_at)        WHERE deleted_at IS NULL;
CREATE INDEX idx_properties_tags         ON properties USING GIN (tags);
CREATE INDEX idx_properties_title_trgm   ON properties USING GIN (title gin_trgm_ops);

CREATE TRIGGER trg_properties_updated_at
    BEFORE UPDATE ON properties
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE property_images (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id   UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    uploader_id   UUID        REFERENCES users (id) ON DELETE SET NULL,
    url           TEXT        NOT NULL,
    thumbnail_url TEXT,
    alt_text      VARCHAR(255),
    caption       TEXT,
    is_primary    BOOLEAN     NOT NULL DEFAULT FALSE,
    display_order INTEGER     NOT NULL DEFAULT 0,
    file_size_kb  INTEGER,
    width         INTEGER,
    height        INTEGER,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ
);

CREATE INDEX idx_property_images_property_id ON property_images (property_id);
CREATE INDEX idx_property_images_primary     ON property_images (property_id, is_primary);

-- -------------------------------------------------------

CREATE TABLE property_videos (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id      UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    uploader_id      UUID        REFERENCES users (id) ON DELETE SET NULL,
    title            VARCHAR(255),
    url              TEXT        NOT NULL,
    thumbnail_url    TEXT,
    video_type       VARCHAR(20) NOT NULL DEFAULT 'upload',
    duration_seconds INTEGER,
    is_primary       BOOLEAN     NOT NULL DEFAULT FALSE,
    display_order    INTEGER     NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ,
    CONSTRAINT chk_video_type CHECK (video_type IN ('upload','youtube','vimeo'))
);

CREATE INDEX idx_property_videos_property_id ON property_videos (property_id);

-- -------------------------------------------------------

CREATE TABLE property_amenities (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(100) NOT NULL,
    slug       VARCHAR(120) NOT NULL,
    category   VARCHAR(50),
    icon_url   TEXT,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_property_amenities_slug UNIQUE (slug)
);

CREATE INDEX idx_property_amenities_category ON property_amenities (category);

-- -------------------------------------------------------

CREATE TABLE property_amenity_map (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID         NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    amenity_id  UUID         NOT NULL REFERENCES property_amenities (id) ON DELETE CASCADE,
    notes       VARCHAR(255),
    CONSTRAINT uq_property_amenity_map UNIQUE (property_id, amenity_id)
);

CREATE INDEX idx_property_amenity_map_property_id ON property_amenity_map (property_id);
CREATE INDEX idx_property_amenity_map_amenity_id  ON property_amenity_map (amenity_id);

-- -------------------------------------------------------

CREATE TABLE property_documents (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id   UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    uploader_id   UUID        REFERENCES users (id) ON DELETE SET NULL,
    document_type VARCHAR(100) NOT NULL,
    title         VARCHAR(255) NOT NULL,
    file_url      TEXT        NOT NULL,
    file_name     VARCHAR(255),
    file_size_kb  INTEGER,
    mime_type     VARCHAR(100),
    is_verified   BOOLEAN     NOT NULL DEFAULT FALSE,
    verified_by   UUID        REFERENCES users (id) ON DELETE SET NULL,
    verified_at   TIMESTAMPTZ,
    expires_at    TIMESTAMPTZ,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ
);

CREATE INDEX idx_property_documents_property_id ON property_documents (property_id);

-- -------------------------------------------------------

CREATE TABLE property_status_logs (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID            NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    changed_by  UUID            REFERENCES users (id) ON DELETE SET NULL,
    old_status  property_status,
    new_status  property_status NOT NULL,
    reason      TEXT,
    notes       TEXT,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_property_status_logs_property_id ON property_status_logs (property_id);
CREATE INDEX idx_property_status_logs_created_at  ON property_status_logs (created_at);

-- -------------------------------------------------------

CREATE TABLE property_views (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    user_id     UUID        REFERENCES users (id) ON DELETE SET NULL,
    ip_address  INET,
    user_agent  TEXT,
    referrer    TEXT,
    session_id  VARCHAR(100),
    viewed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_property_views_property_id ON property_views (property_id);
CREATE INDEX idx_property_views_user_id     ON property_views (user_id)    WHERE user_id IS NOT NULL;
CREATE INDEX idx_property_views_viewed_at   ON property_views (viewed_at);

-- -------------------------------------------------------

CREATE TABLE favorites (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    property_id UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_favorites UNIQUE (user_id, property_id)
);

CREATE INDEX idx_favorites_user_id     ON favorites (user_id);
CREATE INDEX idx_favorites_property_id ON favorites (property_id);


-- ============================================================
-- SERVICE PACKAGES  (declared early — referenced by vr_design_requests)
-- ============================================================

CREATE TABLE service_packages (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name               VARCHAR(150) NOT NULL,
    slug               VARCHAR(180) NOT NULL,
    service_type       service_type NOT NULL,
    description        TEXT,
    features           JSONB,
    price              NUMERIC(15,2) NOT NULL,
    currency           VARCHAR(3)   NOT NULL DEFAULT 'VND',
    duration_days      INTEGER,
    listing_limit      INTEGER,
    featured_days      INTEGER,
    vr_tours_included  INTEGER,
    is_active          BOOLEAN      NOT NULL DEFAULT TRUE,
    display_order      INTEGER      NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_service_packages_slug UNIQUE (slug),
    CONSTRAINT chk_service_packages_price CHECK (price >= 0)
);

CREATE INDEX idx_service_packages_service_type ON service_packages (service_type);
CREATE INDEX idx_service_packages_is_active    ON service_packages (is_active);

CREATE TRIGGER trg_service_packages_updated_at
    BEFORE UPDATE ON service_packages
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- VR MODULE
-- ============================================================

CREATE TABLE property_vr_tours (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id   UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    created_by    UUID        REFERENCES users (id) ON DELETE SET NULL,
    title         VARCHAR(255) NOT NULL,
    description   TEXT,
    tour_url      TEXT        NOT NULL,
    embed_code    TEXT,
    thumbnail_url TEXT,
    tour_type     VARCHAR(50) NOT NULL DEFAULT 'custom_360',
    is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
    view_count    INTEGER     NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_property_vr_tours_property_id ON property_vr_tours (property_id);
CREATE INDEX idx_property_vr_tours_active      ON property_vr_tours (property_id, is_active);

CREATE TRIGGER trg_property_vr_tours_updated_at
    BEFORE UPDATE ON property_vr_tours
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE vr_design_requests (
    id                UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id      UUID              NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    property_id       UUID              REFERENCES properties (id) ON DELETE SET NULL,
    package_id        UUID              REFERENCES service_packages (id) ON DELETE SET NULL,
    title             VARCHAR(300)      NOT NULL,
    description       TEXT,
    requirements      TEXT,
    style_preferences TEXT,
    estimated_area    NUMERIC(10,2),
    budget            NUMERIC(15,2),
    currency          VARCHAR(3)        NOT NULL DEFAULT 'VND',
    status            vr_request_status NOT NULL DEFAULT 'pending',
    priority          SMALLINT          NOT NULL DEFAULT 1,
    due_date          DATE,
    completed_at      TIMESTAMPTZ,
    rejected_at       TIMESTAMPTZ,
    rejection_reason  TEXT,
    admin_notes       TEXT,
    created_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_vr_priority CHECK (priority BETWEEN 1 AND 3)
);

CREATE INDEX idx_vr_design_requests_requester_id ON vr_design_requests (requester_id);
CREATE INDEX idx_vr_design_requests_status       ON vr_design_requests (status);
CREATE INDEX idx_vr_design_requests_property_id  ON vr_design_requests (property_id) WHERE property_id IS NOT NULL;

CREATE TRIGGER trg_vr_design_requests_updated_at
    BEFORE UPDATE ON vr_design_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE vr_design_progress (
    id                    UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id            UUID               NOT NULL REFERENCES vr_design_requests (id) ON DELETE CASCADE,
    updated_by            UUID               REFERENCES users (id) ON DELETE SET NULL,
    status                vr_progress_status NOT NULL,
    milestone_name        VARCHAR(255),
    description           TEXT,
    completion_percentage SMALLINT           NOT NULL DEFAULT 0,
    notes                 TEXT,
    created_at            TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_vr_progress_pct CHECK (completion_percentage BETWEEN 0 AND 100)
);

CREATE INDEX idx_vr_design_progress_request_id ON vr_design_progress (request_id);

-- -------------------------------------------------------

CREATE TABLE vr_design_files (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id     UUID        NOT NULL REFERENCES vr_design_requests (id) ON DELETE CASCADE,
    uploaded_by    UUID        REFERENCES users (id) ON DELETE SET NULL,
    file_type      VARCHAR(50) NOT NULL,
    title          VARCHAR(255),
    description    TEXT,
    file_url       TEXT        NOT NULL,
    file_name      VARCHAR(255),
    file_size_kb   INTEGER,
    mime_type      VARCHAR(100),
    is_deliverable BOOLEAN     NOT NULL DEFAULT FALSE,
    version        VARCHAR(50),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMPTZ
);

CREATE INDEX idx_vr_design_files_request_id    ON vr_design_files (request_id);
CREATE INDEX idx_vr_design_files_deliverables  ON vr_design_files (request_id, is_deliverable);

-- -------------------------------------------------------

CREATE TABLE vr_design_assignments (
    id           UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id   UUID              NOT NULL REFERENCES vr_design_requests (id) ON DELETE CASCADE,
    staff_id     UUID              NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    assigned_by  UUID              REFERENCES users (id) ON DELETE SET NULL,
    role         VARCHAR(100)      NOT NULL DEFAULT 'designer',
    status       assignment_status NOT NULL DEFAULT 'assigned',
    notes        TEXT,
    assigned_at  TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    accepted_at  TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_vr_design_assignments_request_id ON vr_design_assignments (request_id);
CREATE INDEX idx_vr_design_assignments_staff_id   ON vr_design_assignments (staff_id);


-- ============================================================
-- BOOKING / CONTACT
-- ============================================================

CREATE TABLE bookings (
    id                  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id         UUID           NOT NULL REFERENCES properties (id) ON DELETE RESTRICT,
    user_id             UUID           NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    booking_reference   VARCHAR(50)    NOT NULL,
    booking_type        VARCHAR(50)    NOT NULL DEFAULT 'viewing',
    scheduled_date      DATE           NOT NULL,
    scheduled_time      TIME,
    duration_minutes    INTEGER        NOT NULL DEFAULT 60,
    status              booking_status NOT NULL DEFAULT 'pending',
    notes               TEXT,
    owner_notes         TEXT,
    cancellation_reason TEXT,
    cancelled_by        UUID           REFERENCES users (id) ON DELETE SET NULL,
    confirmed_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_bookings_reference UNIQUE (booking_reference)
);

CREATE INDEX idx_bookings_property_id    ON bookings (property_id);
CREATE INDEX idx_bookings_user_id        ON bookings (user_id);
CREATE INDEX idx_bookings_status         ON bookings (status);
CREATE INDEX idx_bookings_scheduled_date ON bookings (scheduled_date);

CREATE TRIGGER trg_bookings_updated_at
    BEFORE UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE booking_status_logs (
    id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID           NOT NULL REFERENCES bookings (id) ON DELETE CASCADE,
    changed_by UUID           REFERENCES users (id) ON DELETE SET NULL,
    old_status booking_status,
    new_status booking_status NOT NULL,
    reason     TEXT,
    created_at TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_booking_status_logs_booking_id ON booking_status_logs (booking_id);

-- -------------------------------------------------------

CREATE TABLE property_reviews (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id      UUID        NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    user_id          UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    booking_id       UUID        REFERENCES bookings (id) ON DELETE SET NULL,
    rating           SMALLINT    NOT NULL,
    title            VARCHAR(255),
    body             TEXT,
    is_verified_visit BOOLEAN    NOT NULL DEFAULT FALSE,
    is_published     BOOLEAN     NOT NULL DEFAULT FALSE,
    moderated_by     UUID        REFERENCES users (id) ON DELETE SET NULL,
    moderated_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at       TIMESTAMPTZ,
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX idx_property_reviews_property_id ON property_reviews (property_id);
CREATE INDEX idx_property_reviews_user_id     ON property_reviews (user_id);
CREATE INDEX idx_property_reviews_published   ON property_reviews (property_id, is_published);

CREATE TRIGGER trg_property_reviews_updated_at
    BEFORE UPDATE ON property_reviews
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE inquiries (
    id            UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id   UUID           NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    sender_id     UUID           REFERENCES users (id) ON DELETE SET NULL,
    sender_name   VARCHAR(255),
    sender_email  VARCHAR(255),
    sender_phone  VARCHAR(20),
    subject       VARCHAR(300),
    message       TEXT           NOT NULL,
    status        inquiry_status NOT NULL DEFAULT 'new',
    reply_message TEXT,
    replied_by    UUID           REFERENCES users (id) ON DELETE SET NULL,
    replied_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_inquiries_property_id ON inquiries (property_id);
CREATE INDEX idx_inquiries_sender_id   ON inquiries (sender_id) WHERE sender_id IS NOT NULL;
CREATE INDEX idx_inquiries_status      ON inquiries (status);

CREATE TRIGGER trg_inquiries_updated_at
    BEFORE UPDATE ON inquiries
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE contact_requests (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID        REFERENCES users (id) ON DELETE SET NULL,
    name             VARCHAR(255) NOT NULL,
    email            VARCHAR(255) NOT NULL,
    phone            VARCHAR(20),
    subject          VARCHAR(300),
    message          TEXT        NOT NULL,
    status           VARCHAR(50) NOT NULL DEFAULT 'pending',
    assigned_to      UUID        REFERENCES users (id) ON DELETE SET NULL,
    resolved_at      TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contact_requests_user_id ON contact_requests (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_contact_requests_status  ON contact_requests (status);

CREATE TRIGGER trg_contact_requests_updated_at
    BEFORE UPDATE ON contact_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- ADMIN / MODERATION
-- ============================================================

CREATE TABLE admin_reviews (
    id               UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id      UUID            NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    reviewed_by      UUID            NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    decision         review_decision NOT NULL,
    feedback         TEXT,
    checklist_passed BOOLEAN         NOT NULL DEFAULT FALSE,
    internal_notes   TEXT,
    previous_status  property_status,
    new_status       property_status,
    reviewed_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_reviews_property_id ON admin_reviews (property_id);
CREATE INDEX idx_admin_reviews_reviewed_by ON admin_reviews (reviewed_by);
CREATE INDEX idx_admin_reviews_decision    ON admin_reviews (decision);

-- -------------------------------------------------------

CREATE TABLE reports (
    id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id          UUID          NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    reported_property_id UUID          REFERENCES properties (id) ON DELETE CASCADE,
    reported_user_id     UUID          REFERENCES users (id) ON DELETE CASCADE,
    report_type          VARCHAR(100)  NOT NULL,
    description          TEXT          NOT NULL,
    evidence_urls        TEXT[],
    status               report_status NOT NULL DEFAULT 'pending',
    resolved_by          UUID          REFERENCES users (id) ON DELETE SET NULL,
    resolved_at          TIMESTAMPTZ,
    resolution_notes     TEXT,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reports_reporter_id          ON reports (reporter_id);
CREATE INDEX idx_reports_reported_property_id ON reports (reported_property_id) WHERE reported_property_id IS NOT NULL;
CREATE INDEX idx_reports_status               ON reports (status);

CREATE TRIGGER trg_reports_updated_at
    BEFORE UPDATE ON reports
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE audit_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    UUID        REFERENCES users (id) ON DELETE SET NULL,
    actor_role  VARCHAR(50),
    action      VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id   UUID,
    old_value   JSONB,
    new_value   JSONB,
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_actor_id   ON audit_logs (actor_id)                  WHERE actor_id IS NOT NULL;
CREATE INDEX idx_audit_logs_action     ON audit_logs (action);
CREATE INDEX idx_audit_logs_entity     ON audit_logs (entity_type, entity_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs (created_at);


-- ============================================================
-- SERVICE / COMMERCE (continued)
-- ============================================================

CREATE TABLE property_package_orders (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    property_id  UUID        REFERENCES properties (id) ON DELETE SET NULL,
    package_id   UUID        NOT NULL REFERENCES service_packages (id) ON DELETE RESTRICT,
    status       VARCHAR(50) NOT NULL DEFAULT 'pending',
    quantity     INTEGER     NOT NULL DEFAULT 1,
    unit_price   NUMERIC(15,2) NOT NULL,
    total_amount NUMERIC(15,2) NOT NULL,
    currency     VARCHAR(3)  NOT NULL DEFAULT 'VND',
    starts_at    TIMESTAMPTZ,
    expires_at   TIMESTAMPTZ,
    activated_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_ppo_status CHECK (status IN ('pending','active','expired','cancelled'))
);

CREATE INDEX idx_ppo_user_id     ON property_package_orders (user_id);
CREATE INDEX idx_ppo_property_id ON property_package_orders (property_id) WHERE property_id IS NOT NULL;
CREATE INDEX idx_ppo_package_id  ON property_package_orders (package_id);
CREATE INDEX idx_ppo_status      ON property_package_orders (status);

CREATE TRIGGER trg_property_package_orders_updated_at
    BEFORE UPDATE ON property_package_orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- PAYMENTS / INVOICES
-- ============================================================

CREATE TABLE payments (
    id                     UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                UUID           NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    package_order_id       UUID           REFERENCES property_package_orders (id) ON DELETE SET NULL,
    vr_request_id          UUID           REFERENCES vr_design_requests (id) ON DELETE SET NULL,
    payment_reference      VARCHAR(100)   NOT NULL,
    payment_type           payment_type   NOT NULL,
    amount                 NUMERIC(15,2)  NOT NULL,
    currency               VARCHAR(3)     NOT NULL DEFAULT 'VND',
    status                 payment_status NOT NULL DEFAULT 'pending',
    payment_method         VARCHAR(50),
    payment_gateway        VARCHAR(50),
    gateway_transaction_id VARCHAR(200),
    gateway_response       JSONB,
    paid_at                TIMESTAMPTZ,
    failed_at              TIMESTAMPTZ,
    failed_reason          TEXT,
    expires_at             TIMESTAMPTZ,
    metadata               JSONB,
    created_at             TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_payments_reference UNIQUE (payment_reference),
    CONSTRAINT chk_payments_amount   CHECK (amount > 0)
);

CREATE INDEX idx_payments_user_id          ON payments (user_id);
CREATE INDEX idx_payments_status           ON payments (status);
CREATE INDEX idx_payments_payment_type     ON payments (payment_type);
CREATE INDEX idx_payments_package_order_id ON payments (package_order_id) WHERE package_order_id IS NOT NULL;
CREATE INDEX idx_payments_vr_request_id    ON payments (vr_request_id)    WHERE vr_request_id IS NOT NULL;
CREATE INDEX idx_payments_created_at       ON payments (created_at);

CREATE TRIGGER trg_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE invoices (
    id              UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id      UUID           NOT NULL REFERENCES payments (id) ON DELETE RESTRICT,
    user_id         UUID           NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    invoice_number  VARCHAR(50)    NOT NULL,
    status          invoice_status NOT NULL DEFAULT 'draft',
    subtotal        NUMERIC(15,2)  NOT NULL DEFAULT 0,
    discount_amount NUMERIC(15,2)  NOT NULL DEFAULT 0,
    tax_amount      NUMERIC(15,2)  NOT NULL DEFAULT 0,
    total_amount    NUMERIC(15,2)  NOT NULL,
    currency        VARCHAR(3)     NOT NULL DEFAULT 'VND',
    notes           TEXT,
    issued_at       TIMESTAMPTZ,
    due_date        DATE,
    paid_at         TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ,
    billing_name    VARCHAR(255),
    billing_email   VARCHAR(255),
    billing_phone   VARCHAR(20),
    billing_address TEXT,
    billing_tax_id  VARCHAR(50),
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_invoices_payment_id  UNIQUE (payment_id),
    CONSTRAINT uq_invoices_number      UNIQUE (invoice_number),
    CONSTRAINT chk_invoices_total      CHECK (total_amount >= 0)
);

CREATE INDEX idx_invoices_user_id   ON invoices (user_id);
CREATE INDEX idx_invoices_status    ON invoices (status);
CREATE INDEX idx_invoices_issued_at ON invoices (issued_at);

CREATE TRIGGER trg_invoices_updated_at
    BEFORE UPDATE ON invoices
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -------------------------------------------------------

CREATE TABLE invoice_items (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id       UUID         NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
    description      VARCHAR(500) NOT NULL,
    quantity         INTEGER      NOT NULL DEFAULT 1,
    unit_price       NUMERIC(15,2) NOT NULL,
    discount_percent NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    tax_percent      NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    subtotal         NUMERIC(15,2) NOT NULL,
    total            NUMERIC(15,2) NOT NULL,
    item_type        VARCHAR(50),
    reference_id     UUID,
    reference_type   VARCHAR(100),
    display_order    INTEGER      NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_invoice_item_qty CHECK (quantity > 0)
);

CREATE INDEX idx_invoice_items_invoice_id ON invoice_items (invoice_id);

-- -------------------------------------------------------

CREATE TABLE refunds (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id        UUID          NOT NULL REFERENCES payments (id) ON DELETE RESTRICT,
    requested_by      UUID          NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    processed_by      UUID          REFERENCES users (id) ON DELETE SET NULL,
    refund_reference  VARCHAR(100)  NOT NULL,
    amount            NUMERIC(15,2) NOT NULL,
    currency          VARCHAR(3)    NOT NULL DEFAULT 'VND',
    status            refund_status NOT NULL DEFAULT 'requested',
    reason            TEXT          NOT NULL,
    admin_notes       TEXT,
    gateway_refund_id VARCHAR(200),
    gateway_response  JSONB,
    requested_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    processed_at      TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    rejected_at       TIMESTAMPTZ,
    rejection_reason  TEXT,
    CONSTRAINT uq_refunds_reference  UNIQUE (refund_reference),
    CONSTRAINT chk_refunds_amount    CHECK (amount > 0)
);

CREATE INDEX idx_refunds_payment_id   ON refunds (payment_id);
CREATE INDEX idx_refunds_requested_by ON refunds (requested_by);
CREATE INDEX idx_refunds_status       ON refunds (status);


-- ============================================================
-- SYSTEM
-- ============================================================

CREATE TABLE notifications (
    id                  UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID              NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    type                notification_type NOT NULL,
    title               VARCHAR(300)      NOT NULL,
    body                TEXT,
    data                JSONB,
    is_read             BOOLEAN           NOT NULL DEFAULT FALSE,
    read_at             TIMESTAMPTZ,
    related_entity_type VARCHAR(100),
    related_entity_id   UUID,
    sent_via            TEXT[],
    created_at          TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id  ON notifications (user_id);
CREATE INDEX idx_notifications_unread   ON notifications (user_id, created_at) WHERE is_read = FALSE;
CREATE INDEX idx_notifications_created  ON notifications (created_at);

-- -------------------------------------------------------

CREATE TABLE search_history (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        REFERENCES users (id) ON DELETE CASCADE,
    session_id   VARCHAR(100),
    query        TEXT,
    filters      JSONB,
    result_count INTEGER,
    ip_address   INET,
    searched_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_search_history_user_id    ON search_history (user_id)    WHERE user_id IS NOT NULL;
CREATE INDEX idx_search_history_searched_at ON search_history (searched_at);

-- -------------------------------------------------------

CREATE TABLE system_settings (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    key         VARCHAR(200) NOT NULL,
    value       TEXT,
    value_type  VARCHAR(20)  NOT NULL DEFAULT 'string',
    label       VARCHAR(255),
    description TEXT,
    group_name  VARCHAR(100),
    is_public   BOOLEAN      NOT NULL DEFAULT FALSE,
    is_editable BOOLEAN      NOT NULL DEFAULT TRUE,
    updated_by  UUID         REFERENCES users (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_system_settings_key UNIQUE (key),
    CONSTRAINT chk_settings_value_type CHECK (value_type IN ('string','integer','boolean','json','decimal'))
);

CREATE INDEX idx_system_settings_group_name ON system_settings (group_name);
CREATE INDEX idx_system_settings_is_public  ON system_settings (is_public);

CREATE TRIGGER trg_system_settings_updated_at
    BEFORE UPDATE ON system_settings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- ROOMIFY — SEED DATA
-- ============================================================

-- -------------------------------------------------------
-- ROLES
-- -------------------------------------------------------
INSERT INTO roles (id, name, display_name, description, is_system) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'admin',    'Administrator',    'Full system access',                    TRUE),
    ('a0000000-0000-0000-0000-000000000002', 'owner',    'Property Owner',   'Can list and manage own properties',    TRUE),
    ('a0000000-0000-0000-0000-000000000003', 'staff',    'Platform Staff',   'Internal staff for VR design & support',TRUE),
    ('a0000000-0000-0000-0000-000000000004', 'customer', 'Customer',         'Registered users who browse and book',  TRUE);


-- -------------------------------------------------------
-- PERMISSIONS
-- -------------------------------------------------------
INSERT INTO permissions (id, name, display_name, module) VALUES
    -- User management
    ('b0000000-0000-0000-0000-000000000001', 'user:read',          'View Users',             'user'),
    ('b0000000-0000-0000-0000-000000000002', 'user:write',         'Create / Edit Users',    'user'),
    ('b0000000-0000-0000-0000-000000000003', 'user:delete',        'Delete Users',           'user'),
    ('b0000000-0000-0000-0000-000000000004', 'user:suspend',       'Suspend Users',          'user'),
    -- Property management
    ('b0000000-0000-0000-0000-000000000010', 'property:read',      'View Properties',        'property'),
    ('b0000000-0000-0000-0000-000000000011', 'property:create',    'Create Properties',      'property'),
    ('b0000000-0000-0000-0000-000000000012', 'property:edit_own',  'Edit Own Properties',    'property'),
    ('b0000000-0000-0000-0000-000000000013', 'property:edit_any',  'Edit Any Property',      'property'),
    ('b0000000-0000-0000-0000-000000000014', 'property:delete',    'Delete Properties',      'property'),
    ('b0000000-0000-0000-0000-000000000015', 'property:approve',   'Approve / Reject Listing','property'),
    ('b0000000-0000-0000-0000-000000000016', 'property:feature',   'Feature Properties',     'property'),
    -- Booking management
    ('b0000000-0000-0000-0000-000000000020', 'booking:read',       'View Bookings',          'booking'),
    ('b0000000-0000-0000-0000-000000000021', 'booking:create',     'Create Bookings',        'booking'),
    ('b0000000-0000-0000-0000-000000000022', 'booking:manage',     'Manage All Bookings',    'booking'),
    -- VR module
    ('b0000000-0000-0000-0000-000000000030', 'vr:request',         'Submit VR Requests',     'vr'),
    ('b0000000-0000-0000-0000-000000000031', 'vr:manage',          'Manage VR Requests',     'vr'),
    ('b0000000-0000-0000-0000-000000000032', 'vr:assign',          'Assign VR Staff',        'vr'),
    -- Payment module
    ('b0000000-0000-0000-0000-000000000040', 'payment:read',       'View Payments',          'payment'),
    ('b0000000-0000-0000-0000-000000000041', 'payment:manage',     'Manage Payments',        'payment'),
    ('b0000000-0000-0000-0000-000000000042', 'payment:refund',     'Process Refunds',        'payment'),
    -- Admin module
    ('b0000000-0000-0000-0000-000000000050', 'admin:dashboard',    'Access Admin Dashboard', 'admin'),
    ('b0000000-0000-0000-0000-000000000051', 'admin:reports',      'View Reports',           'admin'),
    ('b0000000-0000-0000-0000-000000000052', 'admin:settings',     'Manage Settings',        'admin'),
    ('b0000000-0000-0000-0000-000000000053', 'admin:audit_logs',   'View Audit Logs',        'admin');


-- -------------------------------------------------------
-- ROLE-PERMISSION MAPPINGS
-- -------------------------------------------------------

-- Admin: all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a0000000-0000-0000-0000-000000000001', id FROM permissions;

-- Owner permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a0000000-0000-0000-0000-000000000002', id
FROM permissions
WHERE name IN (
    'property:read', 'property:create', 'property:edit_own',
    'booking:read',  'vr:request',       'payment:read'
);

-- Staff permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a0000000-0000-0000-0000-000000000003', id
FROM permissions
WHERE name IN (
    'property:read',    'booking:read',   'booking:manage',
    'vr:manage',        'vr:assign',      'payment:read',
    'admin:dashboard',  'admin:reports'
);

-- Customer permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'a0000000-0000-0000-0000-000000000004', id
FROM permissions
WHERE name IN ('property:read', 'booking:create', 'vr:request');


-- -------------------------------------------------------
-- SERVICE PACKAGES
-- -------------------------------------------------------
INSERT INTO service_packages
    (id, name, slug, service_type, description, features, price, currency,
     duration_days, listing_limit, featured_days, vr_tours_included, is_active, display_order)
VALUES
(
    'c0000000-0000-0000-0000-000000000001',
    'Basic Listing', 'listing-basic', 'listing_basic',
    'Standard 30-day property listing for individual owners.',
    '["Up to 10 photos","Basic listing page","30-day active period","Contact form enabled"]',
    299000, 'VND', 30, 1, 0, 0, TRUE, 1
),
(
    'c0000000-0000-0000-0000-000000000002',
    'Featured Listing', 'listing-featured', 'listing_featured',
    'Highlighted listing at the top of search results for 60 days.',
    '["Up to 20 photos","Featured badge","Homepage spotlight","60-day active period","Priority search ranking"]',
    699000, 'VND', 60, 1, 30, 0, TRUE, 2
),
(
    'c0000000-0000-0000-0000-000000000003',
    'Premium Listing', 'listing-premium', 'listing_premium',
    'Maximum visibility package for agencies and serious sellers.',
    '["Unlimited photos","Video support","Featured badge","90-day active period","Top search placement","Analytics dashboard"]',
    1499000, 'VND', 90, 5, 90, 1, TRUE, 3
),
(
    'c0000000-0000-0000-0000-000000000004',
    'Basic VR Package', 'vr-basic', 'vr_basic',
    'Entry-level VR design service for a single room.',
    '["1 room 3D render","2 revision rounds","Static 360° view","5-business-day delivery"]',
    1990000, 'VND', NULL, NULL, NULL, 1, TRUE, 4
),
(
    'c0000000-0000-0000-0000-000000000005',
    'Advanced VR Package', 'vr-advanced', 'vr_advanced',
    'Full-property interactive VR tour with detailed renders.',
    '["Up to 5 rooms","Unlimited revisions","Interactive VR walkthrough","3D floor plan","10-business-day delivery","Matterport-compatible output"]',
    5990000, 'VND', NULL, NULL, NULL, 3, TRUE, 5
),
(
    'c0000000-0000-0000-0000-000000000006',
    'Custom VR Design', 'vr-custom', 'vr_custom',
    'Fully bespoke VR design — scope confirmed after consultation.',
    '["Custom scope","Dedicated lead designer","Full project management","Complete delivery package"]',
    0, 'VND', NULL, NULL, NULL, NULL, TRUE, 6
);


-- -------------------------------------------------------
-- PROPERTY CATEGORIES
-- -------------------------------------------------------
INSERT INTO property_categories
    (id, parent_id, name, slug, description, display_order, is_active)
VALUES
    -- Top-level
    ('d0000000-0000-0000-0000-000000000001', NULL, 'Residential', 'residential', 'Houses, apartments, and condominiums', 1, TRUE),
    ('d0000000-0000-0000-0000-000000000002', NULL, 'Commercial',  'commercial',  'Office buildings, retail, warehouses',  2, TRUE),
    ('d0000000-0000-0000-0000-000000000003', NULL, 'Land',        'land',        'Land plots and development sites',      3, TRUE),
    ('d0000000-0000-0000-0000-000000000004', NULL, 'Industrial',  'industrial',  'Factories, workshops, logistics',       4, TRUE),
    ('d0000000-0000-0000-0000-000000000005', NULL, 'Hospitality', 'hospitality', 'Hotels, resorts, homestays',            5, TRUE),
    -- Residential sub-categories
    ('d0000000-0000-0000-0000-000000000011', 'd0000000-0000-0000-0000-000000000001', 'Apartment', 'apartment', 'Condominiums and apartment units',    1, TRUE),
    ('d0000000-0000-0000-0000-000000000012', 'd0000000-0000-0000-0000-000000000001', 'House',     'house',     'Detached or semi-detached houses',    2, TRUE),
    ('d0000000-0000-0000-0000-000000000013', 'd0000000-0000-0000-0000-000000000001', 'Villa',     'villa',     'Luxury villas and resort properties', 3, TRUE),
    ('d0000000-0000-0000-0000-000000000014', 'd0000000-0000-0000-0000-000000000001', 'Townhouse', 'townhouse', 'Row houses and linked terraces',      4, TRUE),
    -- Commercial sub-categories
    ('d0000000-0000-0000-0000-000000000021', 'd0000000-0000-0000-0000-000000000002', 'Office',    'office',    'Office spaces and buildings',   1, TRUE),
    ('d0000000-0000-0000-0000-000000000022', 'd0000000-0000-0000-0000-000000000002', 'Retail',    'retail',    'Shops and retail spaces',       2, TRUE),
    ('d0000000-0000-0000-0000-000000000023', 'd0000000-0000-0000-0000-000000000002', 'Warehouse', 'warehouse', 'Storage and logistics spaces',  3, TRUE);


-- -------------------------------------------------------
-- USERS  (password hashes are bcrypt placeholders)
-- -------------------------------------------------------
INSERT INTO users
    (id, email, phone, password_hash, full_name, status, email_verified_at)
VALUES
(
    'e0000000-0000-0000-0000-000000000001',
    'admin@roomify.vn', '0900000001',
    '$2a$12$REPLACE_WITH_REAL_BCRYPT_HASH_ADMIN',
    'Roomify Admin', 'active', NOW()
),
(
    'e0000000-0000-0000-0000-000000000002',
    'owner@roomify.vn', '0900000002',
    '$2a$12$REPLACE_WITH_REAL_BCRYPT_HASH_OWNER',
    'Nguyen Van Owner', 'active', NOW()
),
(
    'e0000000-0000-0000-0000-000000000003',
    'customer@roomify.vn', '0900000003',
    '$2a$12$REPLACE_WITH_REAL_BCRYPT_HASH_USER',
    'Tran Thi Customer', 'active', NOW()
);


-- -------------------------------------------------------
-- USER ROLE ASSIGNMENTS
-- -------------------------------------------------------
INSERT INTO user_roles (user_id, role_id, assigned_by) VALUES
    -- Admin user → admin role (system bootstrap, no assigned_by)
    ('e0000000-0000-0000-0000-000000000001',
     'a0000000-0000-0000-0000-000000000001', NULL),
    -- Owner user → owner role (assigned by admin)
    ('e0000000-0000-0000-0000-000000000002',
     'a0000000-0000-0000-0000-000000000002',
     'e0000000-0000-0000-0000-000000000001'),
    -- Customer user → customer role (assigned by admin)
    ('e0000000-0000-0000-0000-000000000003',
     'a0000000-0000-0000-0000-000000000004',
     'e0000000-0000-0000-0000-000000000001');


-- -------------------------------------------------------
-- OWNER PROFILE
-- -------------------------------------------------------
INSERT INTO owner_profiles
    (user_id, business_name, business_type, bio,
     verified_status, verified_at, verified_by)
VALUES (
    'e0000000-0000-0000-0000-000000000002',
    'Nguyen Van Owner Real Estate', 'individual',
    'Experienced property owner in Ho Chi Minh City with a portfolio of 10+ residential units.',
    'verified', NOW(),
    'e0000000-0000-0000-0000-000000000001'
);


-- -------------------------------------------------------
-- SYSTEM SETTINGS (baseline)
-- -------------------------------------------------------
INSERT INTO system_settings (key, value, value_type, label, group_name, is_public) VALUES
    ('site.name',                  'Roomify',               'string',  'Site Name',                'general', TRUE),
    ('site.currency',              'VND',                   'string',  'Default Currency',          'general', TRUE),
    ('listing.max_images',         '20',                    'integer', 'Max Images per Listing',    'listing', TRUE),
    ('listing.approval_required',  'true',                  'boolean', 'Require Admin Approval',    'listing', FALSE),
    ('listing.featured_price',     '699000',                'decimal', 'Featured Listing Price',    'listing', TRUE),
    ('payment.gateway',            'vnpay',                 'string',  'Default Payment Gateway',   'payment', FALSE),
    ('payment.vat_percent',        '10',                    'decimal', 'VAT Percentage',            'payment', TRUE),
    ('vr.max_files_per_request',   '50',                    'integer', 'Max VR Files per Request',  'vr',      FALSE),
    ('email.from_address',         'no-reply@roomify.vn',  'string',  'System Email Sender',       'email',   FALSE),
    ('email.support_address',      'support@roomify.vn',   'string',  'Support Email Address',     'email',   TRUE);


