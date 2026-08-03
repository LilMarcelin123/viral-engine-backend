-- =====================================================================
-- VIRAL ENGINE — V1: Catálogos y esquema normalizado (MySQL 8 / InnoDB)
-- Normalización: 1FN, 2FN y 3FN. Sin JSON, sin enums duros, sin valores
-- hardcodeados: todo parametrizable vía catálogos y tablas de config.
--
-- Convenciones:
--   * Dinero  -> DECIMAL(12,2)
--   * Fechas  -> DATETIME(6) en UTC
--   * Catálogo-> cat_*  (id, codigo UNIQUE, nombre, activo)
--   * Derivados-> columnas GENERATED o vistas (no se duplican datos)
-- =====================================================================

-- =====================================================================
-- 1. CATÁLOGOS
-- =====================================================================

CREATE TABLE cat_user_type (
    id     TINYINT      NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30)  NOT NULL,
    nombre VARCHAR(80)  NOT NULL,
    activo BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cut_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_user_state (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cus_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- url_regex permite validar dinámicamente que la cuenta corresponda
-- a su red social, sin hardcodear la validación en el código.
CREATE TABLE cat_platform (
    id        TINYINT      NOT NULL AUTO_INCREMENT,
    codigo    VARCHAR(30)  NOT NULL,
    nombre    VARCHAR(80)  NOT NULL,
    dominio   VARCHAR(120) NULL,
    url_regex VARCHAR(255) NULL,
    cuenta_en_bonos BOOLEAN NOT NULL DEFAULT TRUE,   -- ¿sus vistas suman para bonos?
    activo    BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cpl_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_campaign_state (
    id       TINYINT     NOT NULL AUTO_INCREMENT,
    codigo   VARCHAR(30) NOT NULL,
    nombre   VARCHAR(80) NOT NULL,
    es_final BOOLEAN     NOT NULL DEFAULT FALSE,   -- CERRADA/COMPLETADA/CANCELADA
    computa_garantia BOOLEAN NOT NULL DEFAULT FALSE, -- solo ACTIVA compromete saldo
    activo   BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_ccs_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_qa_state (
    id            TINYINT     NOT NULL AUTO_INCREMENT,
    codigo        VARCHAR(30) NOT NULL,
    nombre        VARCHAR(80) NOT NULL,
    paga_base     BOOLEAN     NOT NULL DEFAULT FALSE,  -- APROBADO = TRUE
    participa_bonos BOOLEAN   NOT NULL DEFAULT FALSE,
    activo        BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cqs_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- signo hace la aritmética de la billetera data-driven (+1 suma, -1 resta)
CREATE TABLE cat_movement_type (
    id            TINYINT     NOT NULL AUTO_INCREMENT,
    codigo        VARCHAR(40) NOT NULL,
    nombre        VARCHAR(80) NOT NULL,
    signo         TINYINT     NOT NULL DEFAULT 0,      -- efecto sobre saldo_total
    afecta_saldo  BOOLEAN     NOT NULL DEFAULT FALSE,
    activo        BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cmt_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_payment_state (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cps_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_material_type (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cmat_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_tier_type (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,          -- CLIP (sub-bolsa A) / EDITOR (sub-bolsa B)
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_ctt_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_notification_channel (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cnc_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_notification_type (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(40) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cnt_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_notification_state (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_cns_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 2. CONFIGURACIÓN GLOBAL (parametrizable; nada hardcodeado)
-- =====================================================================

CREATE TABLE app_config (
    id                          TINYINT       NOT NULL,
    precio_por_video            DECIMAL(12,2) NOT NULL DEFAULT 30.00,
    base_por_clip               DECIMAL(12,2) NOT NULL DEFAULT 10.00,
    pct_a                       DECIMAL(5,4)  NOT NULL DEFAULT 0.6000,
    pct_b                       DECIMAL(5,4)  NOT NULL DEFAULT 0.2500,
    pct_c                       DECIMAL(5,4)  NOT NULL DEFAULT 0.1500,
    premio_1_monto_fijo         DECIMAL(12,2) NULL DEFAULT 300.00,  -- NULL => usar pct_c
    max_cuentas_por_plataforma  SMALLINT      NOT NULL DEFAULT 3,
    max_cuentas_total           SMALLINT      NOT NULL DEFAULT 9,
    max_clips_por_cuenta_dia    SMALLINT      NOT NULL DEFAULT 5,
    max_clips_dia               SMALLINT      NOT NULL DEFAULT 15,
    dias_congelado              SMALLINT      NOT NULL DEFAULT 14,
    horas_confirmacion          SMALLINT      NOT NULL DEFAULT 24,
    pct_aprobacion_extras       DECIMAL(5,4)  NOT NULL DEFAULT 0.8500,
    strikes_para_remocion       SMALLINT      NOT NULL DEFAULT 3,
    pct_cap_campana             DECIMAL(5,4)  NOT NULL DEFAULT 0.2500, -- 25% de la campaña
    clips_por_cuenta_dia_cap    DECIMAL(5,2)  NOT NULL DEFAULT 1.50,   -- factor del cap dinámico
    meses_permanencia_clip      SMALLINT      NOT NULL DEFAULT 3,
    score_w_vistas              DECIMAL(5,4)  NOT NULL DEFAULT 0.4000,
    score_w_ganancias           DECIMAL(5,4)  NOT NULL DEFAULT 0.3000,
    score_w_clips               DECIMAL(5,4)  NOT NULL DEFAULT 0.3000,
    updated_at                  DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                              ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT ck_app_config_pcts CHECK (pct_a + pct_b + pct_c = 1.0000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabulador vigente (plantilla). Se copia a cada campaña al crearla.
CREATE TABLE bonus_tier (
    id           BIGINT        NOT NULL AUTO_INCREMENT,
    tier_type_id TINYINT       NOT NULL,
    vistas_min   BIGINT        NOT NULL,
    bono         DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_bonus_tier (tier_type_id, vistas_min),
    CONSTRAINT fk_bt_type FOREIGN KEY (tier_type_id) REFERENCES cat_tier_type (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 3. USUARIOS
-- =====================================================================

CREATE TABLE users (
    id                     BIGINT       NOT NULL AUTO_INCREMENT,
    nombre                 VARCHAR(150) NOT NULL,
    email                  VARCHAR(255) NOT NULL,
    password_hash          VARCHAR(100) NOT NULL,
    user_type_id           TINYINT      NOT NULL,
    user_state_id          TINYINT      NOT NULL,
    telefono               VARCHAR(30)  NULL,
    fecha_nacimiento       DATE         NULL,          -- validar 18+
    correo_paypal          VARCHAR(255) NULL,
    tyc_version            VARCHAR(20)  NULL,
    tyc_aceptado_at        DATETIME(6)  NULL,
    privacidad_aceptada_at DATETIME(6)  NULL,
    created_at             DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_email (email),
    KEY idx_users_type (user_type_id),
    CONSTRAINT fk_users_type  FOREIGN KEY (user_type_id)  REFERENCES cat_user_type (id),
    CONSTRAINT fk_users_state FOREIGN KEY (user_state_id) REFERENCES cat_user_state (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE editor_account (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    user_id     BIGINT       NOT NULL,
    platform_id TINYINT      NOT NULL,
    handle      VARCHAR(150) NULL,
    url         VARCHAR(500) NULL,
    activo      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_editor_account (user_id, platform_id, handle),
    KEY idx_ea_user (user_id),
    CONSTRAINT fk_ea_user     FOREIGN KEY (user_id)     REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_ea_platform FOREIGN KEY (platform_id) REFERENCES cat_platform (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 4. BILLETERA
-- =====================================================================

CREATE TABLE business_wallet (
    id               TINYINT       NOT NULL,
    saldo_total      DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_depositado DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    updated_at       DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                   ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE wallet_movement (
    id               BIGINT        NOT NULL AUTO_INCREMENT,
    movement_type_id TINYINT       NOT NULL,
    monto            DECIMAL(12,2) NOT NULL,
    campaign_id      BIGINT        NULL,
    nota             VARCHAR(500)  NULL,
    hecho_por        BIGINT        NULL,
    created_at       DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_wm_created (created_at),
    KEY idx_wm_campaign (campaign_id),
    CONSTRAINT fk_wm_type FOREIGN KEY (movement_type_id) REFERENCES cat_movement_type (id),
    CONSTRAINT fk_wm_user FOREIGN KEY (hecho_por)        REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 5. CAMPAÑAS  (+ snapshot de configuración normalizado, sin JSON)
-- =====================================================================

CREATE TABLE campaign (
    id                BIGINT        NOT NULL AUTO_INCREMENT,
    nombre            VARCHAR(200)  NOT NULL,
    artista_cancion   VARCHAR(255)  NULL,
    url_audio         VARCHAR(500)  NULL,
    fecha_inicio      DATE          NULL,
    fecha_cierre      DATE          NULL,
    imagen_url        VARCHAR(500)  NULL,
    titulo            VARCHAR(100)  NULL,
    descripcion       VARCHAR(1500) NULL,
    pautas_contenido  TEXT          NULL,
    num_videos        INT           NOT NULL,
    -- Denormalización DELIBERADA (saldo materializado): se bloquea y se
    -- actualiza transaccionalmente; recalcular por SUM en cada lectura
    -- sería incorrecto bajo concurrencia y costoso.
    presupuesto       DECIMAL(12,2) NOT NULL,
    pagado            DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    client_id         BIGINT        NULL,
    campaign_state_id TINYINT       NOT NULL,
    version           BIGINT        NOT NULL DEFAULT 0,
    created_at        DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_campaign_state (campaign_state_id),
    KEY idx_campaign_client (client_id),
    CONSTRAINT fk_campaign_state  FOREIGN KEY (campaign_state_id) REFERENCES cat_campaign_state (id),
    CONSTRAINT fk_campaign_client FOREIGN KEY (client_id)         REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_campaign_pagado CHECK (pagado >= 0 AND pagado <= presupuesto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE wallet_movement
    ADD CONSTRAINT fk_wm_campaign FOREIGN KEY (campaign_id) REFERENCES campaign (id) ON DELETE SET NULL;

-- Snapshot 1:1 de la config vigente al crear la campaña (3FN, sin JSON)
CREATE TABLE campaign_config (
    campaign_id         BIGINT        NOT NULL,
    precio_por_video    DECIMAL(12,2) NOT NULL,
    base_por_clip       DECIMAL(12,2) NOT NULL,
    pct_a               DECIMAL(5,4)  NOT NULL,
    pct_b               DECIMAL(5,4)  NOT NULL,
    pct_c               DECIMAL(5,4)  NOT NULL,
    premio_1_monto_fijo DECIMAL(12,2) NULL,
    dias_congelado      SMALLINT      NOT NULL,
    pct_cap_campana     DECIMAL(5,4)  NOT NULL,
    clips_cuenta_dia    DECIMAL(5,2)  NOT NULL,
    PRIMARY KEY (campaign_id),
    CONSTRAINT fk_cc_campaign FOREIGN KEY (campaign_id) REFERENCES campaign (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Snapshot del tabulador por campaña
CREATE TABLE campaign_bonus_tier (
    id           BIGINT        NOT NULL AUTO_INCREMENT,
    campaign_id  BIGINT        NOT NULL,
    tier_type_id TINYINT       NOT NULL,
    vistas_min   BIGINT        NOT NULL,
    bono         DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cbt (campaign_id, tier_type_id, vistas_min),
    CONSTRAINT fk_cbt_campaign FOREIGN KEY (campaign_id)  REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_cbt_type     FOREIGN KEY (tier_type_id) REFERENCES cat_tier_type (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE campaign_platform (
    campaign_id BIGINT  NOT NULL,
    platform_id TINYINT NOT NULL,
    PRIMARY KEY (campaign_id, platform_id),
    CONSTRAINT fk_cp_campaign FOREIGN KEY (campaign_id) REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_cp_platform FOREIGN KEY (platform_id) REFERENCES cat_platform (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE campaign_material (
    id               BIGINT       NOT NULL AUTO_INCREMENT,
    campaign_id      BIGINT       NOT NULL,
    material_type_id TINYINT      NOT NULL,
    url              VARCHAR(500) NOT NULL,
    PRIMARY KEY (id),
    KEY idx_cm_campaign (campaign_id),
    CONSTRAINT fk_cm_campaign FOREIGN KEY (campaign_id)      REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_cm_type     FOREIGN KEY (material_type_id) REFERENCES cat_material_type (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 6. ASIGNACIONES
-- =====================================================================

CREATE TABLE editor_assignment (
    id              BIGINT      NOT NULL AUTO_INCREMENT,
    campaign_id     BIGINT      NOT NULL,
    user_id         BIGINT      NOT NULL,
    cap_dinamico    INT         NOT NULL DEFAULT 0,
    asignacion_base INT         NOT NULL DEFAULT 0,
    extras          INT         NOT NULL DEFAULT 0,
    confirmado      BOOLEAN     NOT NULL DEFAULT FALSE,
    confirmado_at   DATETIME(6) NULL,
    checkpoint_50   BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_assignment (campaign_id, user_id),
    KEY idx_ea2_user (user_id),
    CONSTRAINT fk_ea2_campaign FOREIGN KEY (campaign_id) REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_ea2_user     FOREIGN KEY (user_id)     REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE assignment_account (
    assignment_id     BIGINT NOT NULL,
    editor_account_id BIGINT NOT NULL,
    PRIMARY KEY (assignment_id, editor_account_id),
    CONSTRAINT fk_aa_assignment FOREIGN KEY (assignment_id)     REFERENCES editor_assignment (id) ON DELETE CASCADE,
    CONSTRAINT fk_aa_account    FOREIGN KEY (editor_account_id) REFERENCES editor_account (id)    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 7. CLIPS
-- =====================================================================

CREATE TABLE clip (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    campaign_id     BIGINT       NOT NULL,
    editor_id       BIGINT       NOT NULL,
    titulo          VARCHAR(200) NULL,
    fecha_publicado DATETIME(6)  NULL,
    fecha_congelado DATETIME(6)  NULL,
    qa_state_id     TINYINT      NOT NULL,
    motivo          VARCHAR(500) NULL,
    excluido_bonos  BOOLEAN      NOT NULL DEFAULT FALSE,  -- vistas infladas: pierde bonos, conserva base
    created_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_clip_campaign (campaign_id),
    KEY idx_clip_editor (editor_id),
    KEY idx_clip_qa (qa_state_id),
    CONSTRAINT fk_clip_campaign FOREIGN KEY (campaign_id) REFERENCES campaign (id),
    CONSTRAINT fk_clip_editor   FOREIGN KEY (editor_id)   REFERENCES users (id),
    CONSTRAINT fk_clip_qa       FOREIGN KEY (qa_state_id) REFERENCES cat_qa_state (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE clip_publication (
    id                BIGINT       NOT NULL AUTO_INCREMENT,
    clip_id           BIGINT       NOT NULL,
    editor_account_id BIGINT       NULL,
    platform_id       TINYINT      NOT NULL,
    link              VARCHAR(500) NOT NULL,
    vistas            BIGINT       NOT NULL DEFAULT 0,
    likes             BIGINT       NOT NULL DEFAULT 0,
    updated_at        DATETIME(6)  NULL,
    PRIMARY KEY (id),
    KEY idx_pub_clip (clip_id),
    CONSTRAINT fk_pub_clip     FOREIGN KEY (clip_id)           REFERENCES clip (id) ON DELETE CASCADE,
    CONSTRAINT fk_pub_account  FOREIGN KEY (editor_account_id) REFERENCES editor_account (id) ON DELETE SET NULL,
    CONSTRAINT fk_pub_platform FOREIGN KEY (platform_id)       REFERENCES cat_platform (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tag normalizado (evita repetir la cadena en cada clip → 3FN)
CREATE TABLE tag (
    id     BIGINT      NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(80) NOT NULL,
    PRIMARY KEY (id), UNIQUE KEY uq_tag_nombre (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE clip_tag (
    clip_id BIGINT NOT NULL,
    tag_id  BIGINT NOT NULL,
    PRIMARY KEY (clip_id, tag_id),
    KEY idx_clip_tag_tag (tag_id),
    CONSTRAINT fk_ct_clip FOREIGN KEY (clip_id) REFERENCES clip (id) ON DELETE CASCADE,
    CONSTRAINT fk_ct_tag  FOREIGN KEY (tag_id)  REFERENCES tag (id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 8. STRIKES (acumulativos de por vida; 3 => usuario REMOVIDO)
-- =====================================================================

CREATE TABLE strike (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    user_id         BIGINT       NOT NULL,
    campaign_id     BIGINT       NULL,
    clip_id         BIGINT       NULL,
    motivo          VARCHAR(500) NOT NULL,
    aplicado_por    BIGINT       NULL,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    removido_por    BIGINT       NULL,
    removido_at     DATETIME(6)  NULL,
    motivo_remocion VARCHAR(500) NULL,
    created_at      DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_strike_user_activo (user_id, activo),
    CONSTRAINT fk_st_user     FOREIGN KEY (user_id)      REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_st_campaign FOREIGN KEY (campaign_id)  REFERENCES campaign (id) ON DELETE SET NULL,
    CONSTRAINT fk_st_clip     FOREIGN KEY (clip_id)      REFERENCES clip (id) ON DELETE SET NULL,
    CONSTRAINT fk_st_aplicado FOREIGN KEY (aplicado_por) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_st_removido FOREIGN KEY (removido_por) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 9. PAGOS  (total es GENERATED: no se almacena un derivado → 3FN)
-- =====================================================================

CREATE TABLE payment (
    id               BIGINT        NOT NULL AUTO_INCREMENT,
    campaign_id      BIGINT        NOT NULL,
    editor_id        BIGINT        NOT NULL,
    pago_base        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    bono_escalon     DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    bono_acumulado   DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    premio_1         DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total            DECIMAL(12,2) AS (pago_base + bono_escalon + bono_acumulado + premio_1) STORED,
    payment_state_id TINYINT       NOT NULL,
    fecha_pago       DATETIME(6)   NULL,
    referencia       VARCHAR(200)  NULL,
    marcado_por      BIGINT        NULL,
    quincena         CHAR(10)      NULL,     -- ej. 2026-07-Q2
    PRIMARY KEY (id),
    UNIQUE KEY uq_payment (campaign_id, editor_id),
    KEY idx_payment_state (payment_state_id),
    KEY idx_payment_quincena (quincena),
    CONSTRAINT fk_pay_campaign FOREIGN KEY (campaign_id)      REFERENCES campaign (id),
    CONSTRAINT fk_pay_editor   FOREIGN KEY (editor_id)        REFERENCES users (id),
    CONSTRAINT fk_pay_state    FOREIGN KEY (payment_state_id) REFERENCES cat_payment_state (id),
    CONSTRAINT fk_pay_marcado  FOREIGN KEY (marcado_por)      REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Auditoría de cada cálculo: guarda el factor de prorrateo aplicado
CREATE TABLE payout_run (
    id              BIGINT        NOT NULL AUTO_INCREMENT,
    campaign_id     BIGINT        NOT NULL,
    ejecutado_por   BIGINT        NULL,
    pool_base       DECIMAL(12,2) NOT NULL,
    bolsa_bonos     DECIMAL(12,2) NOT NULL,
    sub_bolsa_a     DECIMAL(12,2) NOT NULL,
    sub_bolsa_b     DECIMAL(12,2) NOT NULL,
    sub_bolsa_c     DECIMAL(12,2) NOT NULL,
    nominal_a       DECIMAL(12,2) NOT NULL,
    factor_a        DECIMAL(9,6)  NOT NULL DEFAULT 1.000000,
    nominal_b       DECIMAL(12,2) NOT NULL,
    factor_b        DECIMAL(9,6)  NOT NULL DEFAULT 1.000000,
    total_calculado DECIMAL(12,2) NOT NULL,
    created_at      DATETIME(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_pr_campaign (campaign_id),
    CONSTRAINT fk_pr_campaign FOREIGN KEY (campaign_id)   REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_pr_user     FOREIGN KEY (ejecutado_por) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 10. NOTIFICACIONES Y BITÁCORA
-- =====================================================================

CREATE TABLE notification (
    id                       BIGINT       NOT NULL AUTO_INCREMENT,
    user_id                  BIGINT       NULL,
    notification_channel_id  TINYINT      NOT NULL,
    notification_type_id     TINYINT      NOT NULL,
    notification_state_id    TINYINT      NOT NULL,
    destino                  VARCHAR(255) NOT NULL,
    campaign_id              BIGINT       NULL,
    mensaje                  TEXT         NULL,
    error                    VARCHAR(500) NULL,
    enviado_at               DATETIME(6)  NULL,
    created_at               DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_notif_state (notification_state_id),
    CONSTRAINT fk_nt_user     FOREIGN KEY (user_id)                 REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_nt_campaign FOREIGN KEY (campaign_id)             REFERENCES campaign (id) ON DELETE SET NULL,
    CONSTRAINT fk_nt_channel  FOREIGN KEY (notification_channel_id) REFERENCES cat_notification_channel (id),
    CONSTRAINT fk_nt_type     FOREIGN KEY (notification_type_id)    REFERENCES cat_notification_type (id),
    CONSTRAINT fk_nt_state    FOREIGN KEY (notification_state_id)   REFERENCES cat_notification_state (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE audit_log (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NULL,
    accion     VARCHAR(100) NOT NULL,
    detalle    TEXT         NULL,
    created_at DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_audit_created (created_at),
    CONSTRAINT fk_al_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 11. SEED DE CATÁLOGOS
-- =====================================================================

INSERT INTO cat_user_type (codigo, nombre) VALUES
    ('ADMIN','Administrador'), ('CLIENTE','Cliente'), ('EDITOR','Editor');

INSERT INTO cat_user_state (codigo, nombre) VALUES
    ('ACTIVO','Activo'), ('SUSPENDIDO','Suspendido'), ('REMOVIDO','Removido');

INSERT INTO cat_platform (codigo, nombre, dominio, url_regex) VALUES
    ('TIKTOK','TikTok','tiktok.com','^https?://([a-z0-9-]+\\.)?tiktok\\.com/.+$'),
    ('INSTAGRAM','Instagram','instagram.com','^https?://([a-z0-9-]+\\.)?instagram\\.com/.+$'),
    ('YOUTUBE','YouTube','youtube.com','^https?://([a-z0-9-]+\\.)?(youtube\\.com|youtu\\.be)/.+$');

INSERT INTO cat_campaign_state (codigo, nombre, es_final, computa_garantia) VALUES
    ('DRAFT','Borrador',FALSE,FALSE),
    ('ACTIVA','Activa',FALSE,TRUE),
    ('CERRADA','Cerrada',TRUE,FALSE),
    ('COMPLETADA','Completada',TRUE,FALSE),
    ('CANCELADA','Cancelada',TRUE,FALSE);

INSERT INTO cat_qa_state (codigo, nombre, paga_base, participa_bonos) VALUES
    ('SUBIDO','Subido',FALSE,FALSE),
    ('EN_REVISION','En revisión',FALSE,FALSE),
    ('NO_APROBADO','No aprobado',FALSE,FALSE),
    ('APROBADO','Aprobado',TRUE,TRUE);

INSERT INTO cat_movement_type (codigo, nombre, signo, afecta_saldo) VALUES
    ('DEPOSITO','Depósito',1,TRUE),
    ('PAGO_EDITOR','Pago a editor',-1,TRUE),
    ('APARTADO_GARANTIA','Apartado en garantía',0,FALSE),
    ('LIBERACION_GARANTIA','Liberación de garantía',0,FALSE);

INSERT INTO cat_payment_state (codigo, nombre) VALUES
    ('PENDIENTE','Pendiente'), ('PAGADO','Pagado');

INSERT INTO cat_material_type (codigo, nombre) VALUES
    ('LINK','Enlace'), ('ARCHIVO','Archivo');

INSERT INTO cat_tier_type (codigo, nombre) VALUES
    ('CLIP','Escalón por clip (sub-bolsa A)'),
    ('EDITOR','Acumulado por editor (sub-bolsa B)');

INSERT INTO cat_notification_channel (codigo, nombre) VALUES
    ('EMAIL','Correo electrónico'), ('WHATSAPP','WhatsApp');

INSERT INTO cat_notification_type (codigo, nombre) VALUES
    ('NUEVA_CAMPANA','Nueva campaña'), ('STRIKE','Strike aplicado'),
    ('REPORTE_FINAL','Reporte final'), ('PAGO','Pago procesado');

INSERT INTO cat_notification_state (codigo, nombre) VALUES
    ('PENDIENTE','Pendiente'), ('ENVIADO','Enviado'), ('ERROR','Error');

-- Config global y billetera
INSERT INTO app_config (id) VALUES (1);
INSERT INTO business_wallet (id) VALUES (1);

-- Tabulador vigente
INSERT INTO bonus_tier (tier_type_id, vistas_min, bono)
SELECT id, 5000, 10.00    FROM cat_tier_type WHERE codigo='CLIP'
UNION ALL SELECT id, 10000, 25.00   FROM cat_tier_type WHERE codigo='CLIP'
UNION ALL SELECT id, 50000, 75.00   FROM cat_tier_type WHERE codigo='CLIP'
UNION ALL SELECT id, 100000, 200.00 FROM cat_tier_type WHERE codigo='CLIP'
UNION ALL SELECT id, 500000, 600.00 FROM cat_tier_type WHERE codigo='CLIP'
UNION ALL SELECT id, 1000000,1500.00 FROM cat_tier_type WHERE codigo='CLIP'
UNION ALL SELECT id, 50000, 30.00   FROM cat_tier_type WHERE codigo='EDITOR'
UNION ALL SELECT id, 100000, 60.00  FROM cat_tier_type WHERE codigo='EDITOR'
UNION ALL SELECT id, 200000, 120.00 FROM cat_tier_type WHERE codigo='EDITOR';
