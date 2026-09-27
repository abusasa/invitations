// =====================================================================
// ToiTech MVP — config.js
// Подключается тегом <script src="config.js"></script> ДО app-скриптов
// в create.html, index.html и admin.html.
// =====================================================================

// Взять в Supabase Dashboard → Project Settings → API.
// SUPABASE_ANON_KEY — это публичный ключ, его наличие в браузере
// нормально и ожидаемо (для этого и нужен RLS в schema.sql).
window.TOITECH_CONFIG = {
    SUPABASE_URL: "https://YOUR_PROJECT.supabase.co",
    SUPABASE_ANON_KEY: "YOUR_ANON_PUBLIC_KEY",

    // Email админ-аккаунта, созданного в Supabase Dashboard →
    // Authentication → Users → Add user (задать email + пароль там).
    // На экране входа в admin.html пользователь вводит только пароль —
    // email подставляется отсюда автоматически.
    ADMIN_EMAIL: "admin@toitech.kz",

    // Сколько минут длится демо-предпросмотр неоплаченного сайта.
    DEMO_LIMIT_MINUTES: 30,

    // Максимум созданий сайтов с одного устройства в час (rate limit).
    RATE_LIMIT_PER_HOUR: 3
};
