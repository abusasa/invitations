// =====================================================================
// ToiTech MVP — config.js
// Подключается тегом <script src="config.js"></script> ДО app-скриптов
// в create.html, index.html и admin.html.
// =====================================================================

// Можно задать window.__TOITECH_CONFIG__ до подключения этого файла.
// При сборке через Vercel поддерживаются NEXT_PUBLIC_* из process.env.
const injectedConfig = window.__TOITECH_CONFIG__ || window.TOITECH_CONFIG || {};
const buildEnv = typeof process !== 'undefined' && process.env ? process.env : {};

// Взять в Supabase Dashboard → Project Settings → API.
// SUPABASE_ANON_KEY — это публичный ключ, его наличие в браузере
// нормально и ожидаемо (для этого и нужен RLS в schema.sql).
window.TOITECH_CONFIG = {
    ...injectedConfig,
    SUPABASE_URL: injectedConfig.SUPABASE_URL || window.NEXT_PUBLIC_SUPABASE_URL || buildEnv.NEXT_PUBLIC_SUPABASE_URL || "https://jsdddakyslmdoxtlyram.supabase.co",
    SUPABASE_ANON_KEY: injectedConfig.SUPABASE_ANON_KEY || window.NEXT_PUBLIC_SUPABASE_ANON_KEY || buildEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY || "sb_publishable_6vnwk7Wdgf7kOZU86NZ1qw_vzdLI1c",

    // Email админ-аккаунта, созданного в Supabase Dashboard →
    // Authentication → Users → Add user (задать email + пароль там).
    // На экране входа в admin.html пользователь вводит только пароль —
    // email подставляется отсюда автоматически.
    ADMIN_EMAIL: "abdullaabusamat2@gmail.com",

    // Сколько минут длится демо-предпросмотр неоплаченного сайта.
    DEMO_LIMIT_MINUTES: 30,

    // Максимум созданий сайтов с одного устройства в час (rate limit).
    RATE_LIMIT_PER_HOUR: 3
};
