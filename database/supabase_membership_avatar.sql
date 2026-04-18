-- Thêm các cột mới vào bảng users
-- Chạy trong Supabase SQL Editor

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url            TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS membership_start_date TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS membership_expiry_date TIMESTAMPTZ;
