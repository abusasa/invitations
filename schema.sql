-- =====================================================================
-- ToiTech MVP — schema.sql
-- =====================================================================
-- Выполнять в Supabase SQL Editor целиком, сверху вниз.
--
-- ОТСТУПЛЕНИЯ ОТ ИСХОДНОГО ТЗ (и почему):
--   1. Добавлен RLS + функция get_invitation() вместо прямого SELECT
--      анонимом по таблице invitations. Причина: anon-ключ виден в
--      браузере. Без этого любой человек с anon-ключом (он всегда
--      публичный, это нормально для Supabase) мог бы одним запросом
--      выгрузить ВСЮ таблицу invitations — имена и WhatsApp-номера
--      всех клиентов, а не только той записи, что открыта в браузере.
--   2. Добавлен триггер force_draft_on_insert — клиент не может при
--      создании сразу прислать status='paid', даже если отредактирует
--      запрос в devtools.
--   3. UPDATE (подтверждение оплаты) разрешён только authenticated
--      роли — то есть только после входа через Supabase Auth в
--      admin.html (см. комментарий там про ADMIN_EMAIL).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Таблицы (как в ТЗ)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS restaurants (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id BIGINT REFERENCES restaurants(id) ON DELETE SET NULL,
    ref_code VARCHAR(100),
    event_type VARCHAR(100) NOT NULL, -- 'Үйлену той', 'Ұзату той', 'Сүндет той', 'Мерейтой (40/50/60 жас)', 'Бесік той'
    names VARCHAR(255) NOT NULL,
    event_date VARCHAR(255) NOT NULL, -- хранится как ISO 8601 строка (datetime-local из формы), см. create.html
    location_name VARCHAR(255) NOT NULL,
    location_url TEXT NOT NULL,
    template_id VARCHAR(50) DEFAULT 'gold_ornament', -- 'gold_ornament', 'modern_minimal', 'kids_party'
    music_url TEXT,
    client_phone VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'draft', -- 'draft' или 'paid'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE invitations ADD COLUMN IF NOT EXISTS ref_code VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_invitations_created_at ON invitations (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invitations_restaurant_id ON invitations (restaurant_id);

-- Публичный realtime-канал содержит только статус, не телефоны и данные события.
CREATE TABLE IF NOT EXISTS invitation_status (
    id UUID PRIMARY KEY REFERENCES invitations(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

INSERT INTO invitation_status (id, status, updated_at)
SELECT id, status, NOW() FROM invitations
ON CONFLICT (id) DO UPDATE
SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at;

INSERT INTO restaurants (name, slug, phone)
VALUES ('Layeli Palace', 'layeli', '+77000000000')
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Триггер: статус при создании всегда 'draft', что бы ни прислал клиент
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION force_draft_on_insert()
RETURNS TRIGGER AS $$
BEGIN
    NEW.status := 'draft';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_force_draft_on_insert ON invitations;
CREATE TRIGGER trg_force_draft_on_insert
    BEFORE INSERT ON invitations
    FOR EACH ROW
    EXECUTE FUNCTION force_draft_on_insert();

CREATE OR REPLACE FUNCTION sync_invitation_status()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO invitation_status (id, status, updated_at)
    VALUES (NEW.id, NEW.status, NOW())
    ON CONFLICT (id) DO UPDATE
    SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_invitation_status ON invitations;
CREATE TRIGGER trg_sync_invitation_status
    AFTER INSERT OR UPDATE ON invitations
    FOR EACH ROW
    EXECUTE FUNCTION sync_invitation_status();

-- ---------------------------------------------------------------------
-- 3. RLS
-- ---------------------------------------------------------------------

ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitation_status ENABLE ROW LEVEL SECURITY;

-- restaurants: нужно анониму, чтобы create.html мог по ?ref=slug
-- определить restaurant_id. Данные не приватные (название/слаг/телефон
-- ресторана — публичная информация).
DROP POLICY IF EXISTS restaurants_public_select ON restaurants;
CREATE POLICY restaurants_public_select ON restaurants
    FOR SELECT
    USING (true);

-- invitations: анон НЕ получает прямой SELECT (см. пояснение вверху
-- файла). Чтение одной записи идёт только через get_invitation() ниже.

-- Создание черновика доступно всем (это форма на публичном сайте).
DROP POLICY IF EXISTS invitations_public_insert ON invitations;
CREATE POLICY invitations_public_insert ON invitations
    FOR INSERT
    WITH CHECK (true);

-- Полный список и обновление статуса — только вошедшему администратору.
DROP POLICY IF EXISTS invitations_admin_select ON invitations;
CREATE POLICY invitations_admin_select ON invitations
    FOR SELECT
    USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS invitations_admin_update ON invitations;
CREATE POLICY invitations_admin_update ON invitations
    FOR UPDATE
    USING (auth.role() = 'authenticated')
    WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS invitation_status_public_select ON invitation_status;
CREATE POLICY invitation_status_public_select ON invitation_status
    FOR SELECT
    USING (true);

GRANT SELECT ON invitation_status TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON invitation_status FROM anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. RPC-функция: безопасное чтение одного приглашения гостем
-- ---------------------------------------------------------------------
-- SECURITY DEFINER — функция выполняется с правами владельца (обходит
-- RLS изнутри), но наружу отдаёт ровно одну строку по id, без
-- client_phone. Это и есть механизм "гость видит свою страницу, но не
-- видит чужие".

CREATE OR REPLACE FUNCTION get_invitation(p_id UUID)
RETURNS TABLE (
    id UUID,
    event_type VARCHAR,
    names VARCHAR,
    event_date VARCHAR,
    location_name VARCHAR,
    location_url TEXT,
    template_id VARCHAR,
    music_url TEXT,
    status VARCHAR,
    created_at TIMESTAMPTZ,
    restaurant_name VARCHAR
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
AS $$
    SELECT
        i.id, i.event_type, i.names, i.event_date, i.location_name,
        i.location_url, i.template_id, i.music_url, i.status,
        i.created_at, r.name AS restaurant_name
    FROM invitations i
    LEFT JOIN restaurants r ON r.id = i.restaurant_id
    WHERE i.id = p_id;
$$;

GRANT EXECUTE ON FUNCTION get_invitation(UUID) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Realtime (публичная таблица содержит только id и статус)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (
           SELECT 1 FROM pg_publication_tables
           WHERE pubname = 'supabase_realtime'
             AND schemaname = 'public'
             AND tablename = 'invitation_status'
       ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.invitation_status;
    END IF;
END;
$$;
