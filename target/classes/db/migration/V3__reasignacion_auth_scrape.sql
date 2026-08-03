-- =====================================================================
-- VIRAL ENGINE — V3: Bolsa de reasignación, tokens de auth y scrapeo
-- Cliente permanece en modo lectura (sin paquetes/pagos/facturación).
-- =====================================================================

-- =====================================================================
-- 1. CATÁLOGOS NUEVOS
-- =====================================================================

CREATE TABLE cat_reassignment_reason (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(40) NOT NULL,
    nombre VARCHAR(120) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_crr_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cat_scrape_state (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(80) NOT NULL,
    activo BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id), UNIQUE KEY uq_css_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 2. BOLSA DE REASIGNACIÓN
-- Modelo por cantidades (consistente con el cap por contadores):
--   entry  = lote de videos liberados por un editor
--   claim  = videos reclamados por otro editor
--   disponible = SUM(entry.cantidad) - SUM(claim.cantidad)
-- =====================================================================

CREATE TABLE reassignment_entry (
    id                   BIGINT       NOT NULL AUTO_INCREMENT,
    campaign_id          BIGINT       NOT NULL,
    origen_assignment_id BIGINT       NULL,        -- de quién se liberaron
    reason_id            TINYINT      NOT NULL,
    cantidad             INT          NOT NULL,
    nota                 VARCHAR(500) NULL,
    creado_por           BIGINT       NULL,
    created_at           DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_re_campaign (campaign_id),
    CONSTRAINT ck_re_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_re_campaign   FOREIGN KEY (campaign_id)          REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_re_assignment FOREIGN KEY (origen_assignment_id) REFERENCES editor_assignment (id) ON DELETE SET NULL,
    CONSTRAINT fk_re_reason     FOREIGN KEY (reason_id)            REFERENCES cat_reassignment_reason (id),
    CONSTRAINT fk_re_user       FOREIGN KEY (creado_por)           REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE reassignment_claim (
    id            BIGINT      NOT NULL AUTO_INCREMENT,
    campaign_id   BIGINT      NOT NULL,
    assignment_id BIGINT      NOT NULL,            -- quién reclama
    cantidad      INT         NOT NULL,
    created_at    DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_rc_campaign (campaign_id),
    CONSTRAINT ck_rc_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_rc_campaign   FOREIGN KEY (campaign_id)   REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_rc_assignment FOREIGN KEY (assignment_id) REFERENCES editor_assignment (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 3. AUTENTICACIÓN (se guardan HASHES, nunca el token en claro)
-- =====================================================================

CREATE TABLE password_reset_token (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    expira_at  DATETIME(6)  NOT NULL,
    usado_at   DATETIME(6)  NULL,
    created_at DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_prt_hash (token_hash),
    KEY idx_prt_user (user_id),
    CONSTRAINT fk_prt_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE refresh_token (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    user_id     BIGINT       NOT NULL,
    token_hash  VARCHAR(255) NOT NULL,
    expira_at   DATETIME(6)  NOT NULL,
    revocado_at DATETIME(6)  NULL,
    user_agent  VARCHAR(255) NULL,
    ip          VARCHAR(45)  NULL,
    created_at  DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_rt_hash (token_hash),
    KEY idx_rt_user (user_id),
    CONSTRAINT fk_rt_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 4. HISTORIAL DE SCRAPEO (manual)
-- =====================================================================

CREATE TABLE scrape_run (
    id                    BIGINT       NOT NULL AUTO_INCREMENT,
    campaign_id           BIGINT       NULL,          -- NULL = todas las activas
    scrape_state_id       TINYINT      NOT NULL,
    ejecutado_por         BIGINT       NULL,
    publicaciones_actualizadas INT     NOT NULL DEFAULT 0,
    clips_congelados      INT          NOT NULL DEFAULT 0,
    iniciado_at           DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    finalizado_at         DATETIME(6)  NULL,
    error                 VARCHAR(500) NULL,
    PRIMARY KEY (id),
    KEY idx_sr_campaign (campaign_id),
    KEY idx_sr_iniciado (iniciado_at),
    CONSTRAINT fk_sr_campaign FOREIGN KEY (campaign_id)     REFERENCES campaign (id) ON DELETE CASCADE,
    CONSTRAINT fk_sr_state    FOREIGN KEY (scrape_state_id) REFERENCES cat_scrape_state (id),
    CONSTRAINT fk_sr_user     FOREIGN KEY (ejecutado_por)   REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 5. VISTAS
-- =====================================================================

-- Videos disponibles en la bolsa de reasignación, por campaña
CREATE OR REPLACE VIEW v_reassignment_available AS
SELECT c.id AS campaign_id,
       COALESCE((SELECT SUM(e.cantidad) FROM reassignment_entry e WHERE e.campaign_id = c.id),0)
     - COALESCE((SELECT SUM(k.cantidad) FROM reassignment_claim k WHERE k.campaign_id = c.id),0)
       AS disponibles
FROM campaign c;

-- Antigüedad del último scrapeo: sirve para avisar antes de calcular pagos
CREATE OR REPLACE VIEW v_scrape_freshness AS
SELECT c.id AS campaign_id,
       MAX(s.finalizado_at) AS ultimo_scrape,
       TIMESTAMPDIFF(DAY, MAX(s.finalizado_at), NOW()) AS dias_desde_scrape
FROM campaign c
LEFT JOIN scrape_run s
       ON (s.campaign_id = c.id OR s.campaign_id IS NULL)
      AND s.scrape_state_id = (SELECT id FROM cat_scrape_state WHERE codigo='OK')
GROUP BY c.id;

-- =====================================================================
-- 6. PROCEDIMIENTOS
-- =====================================================================
DELIMITER $$

-- Libera videos de un editor a la bolsa (no confirmó, falló checkpoint, strike)
CREATE PROCEDURE sp_reasignacion_liberar(
    IN p_assignment_id BIGINT, IN p_reason_codigo VARCHAR(40),
    IN p_cantidad INT, IN p_user_id BIGINT)
BEGIN
    DECLARE v_campaign BIGINT;
    DECLARE v_reason TINYINT;
    DECLARE v_asignados INT;
    DECLARE v_extras INT;
    DECLARE v_de_extras INT;
    DECLARE v_de_base INT;

    SELECT id INTO v_reason FROM cat_reassignment_reason WHERE codigo = p_reason_codigo;
    IF v_reason IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Motivo de reasignación inválido';
    END IF;

    START TRANSACTION;
        SELECT campaign_id, extras, (asignacion_base + extras)
          INTO v_campaign, v_extras, v_asignados
          FROM editor_assignment WHERE id = p_assignment_id FOR UPDATE;

        IF p_cantidad > v_asignados THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No puede liberar más videos de los asignados';
        END IF;

        -- Se calcula en variables ANTES del UPDATE: MySQL evalúa las
        -- asignaciones de izquierda a derecha con valores ya modificados.
        SET v_de_extras = LEAST(v_extras, p_cantidad);
        SET v_de_base   = p_cantidad - v_de_extras;

        UPDATE editor_assignment
           SET extras = extras - v_de_extras,
               asignacion_base = asignacion_base - v_de_base
         WHERE id = p_assignment_id;

        INSERT INTO reassignment_entry (campaign_id, origen_assignment_id, reason_id, cantidad, creado_por)
        VALUES (v_campaign, p_assignment_id, v_reason, p_cantidad, p_user_id);
    COMMIT;
END$$

-- Reclama videos de la bolsa. Requiere tasa de aprobación >= app_config.
CREATE PROCEDURE sp_reasignacion_reclamar(
    IN p_assignment_id BIGINT, IN p_cantidad INT)
BEGIN
    DECLARE v_campaign BIGINT;
    DECLARE v_user BIGINT;
    DECLARE v_disponibles INT;
    DECLARE v_tasa DECIMAL(9,4);
    DECLARE v_min_tasa DECIMAL(5,4);
    DECLARE v_cap INT;
    DECLARE v_actual INT;

    START TRANSACTION;
        SELECT campaign_id, user_id, cap_dinamico, (asignacion_base + extras)
          INTO v_campaign, v_user, v_cap, v_actual
          FROM editor_assignment WHERE id = p_assignment_id FOR UPDATE;

        -- Serializa reclamos concurrentes de la misma campaña (evita
        -- que dos editores sobre-giren la bolsa al reclamar a la vez)
        SELECT id INTO v_campaign FROM campaign WHERE id = v_campaign FOR UPDATE;

        SELECT pct_aprobacion_extras INTO v_min_tasa FROM app_config WHERE id = 1;
        SELECT tasa_aprobacion INTO v_tasa FROM v_editor_qa_rate WHERE editor_id = v_user;

        IF v_tasa IS NOT NULL AND v_tasa < v_min_tasa THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tasa de aprobación insuficiente para reclamar extras';
        END IF;

        SELECT disponibles INTO v_disponibles FROM v_reassignment_available WHERE campaign_id = v_campaign;
        IF p_cantidad > v_disponibles THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No hay suficientes videos disponibles en la bolsa';
        END IF;

        IF (v_actual + p_cantidad) > v_cap THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Excede el cap dinámico del editor';
        END IF;

        UPDATE editor_assignment SET extras = extras + p_cantidad WHERE id = p_assignment_id;

        INSERT INTO reassignment_claim (campaign_id, assignment_id, cantidad)
        VALUES (v_campaign, p_assignment_id, p_cantidad);
    COMMIT;
END$$

DELIMITER ;

-- =====================================================================
-- 7. SEED
-- =====================================================================

INSERT INTO cat_reassignment_reason (codigo, nombre) VALUES
    ('NO_CONFIRMO','No confirmó en 24 horas'),
    ('CHECKPOINT_50','No cumplió el checkpoint del 50%'),
    ('STRIKE_REMOCION','Editor removido por strikes'),
    ('MANUAL','Liberación manual del administrador');

INSERT INTO cat_scrape_state (codigo, nombre) VALUES
    ('EJECUTANDO','En ejecución'), ('OK','Completado'), ('ERROR','Con error');
