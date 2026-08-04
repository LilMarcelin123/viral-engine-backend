-- =====================================================================
-- V11 — El dinero que se debe sigue reservado hasta que se paga de verdad.
--
-- Dos huecos que se corrigen aquí:
--
-- 1) Cerrar una campaña liberaba TODA la garantía aunque quedaran pagos
--    PENDIENTES. Como `pagado` solo sube al marcar pagado, una campaña con
--    $700 calculados y $0 marcados liberaba los $1,000 completos. Ese dinero
--    quedaba disponible para activar otra campaña mientras la deuda con los
--    editores seguía viva y pagable.
--
-- 2) sp_payment_marcar_pagado validaba contra `saldo_total`, que incluye la
--    garantía de OTRAS campañas activas. Se podía pagar a los editores de la
--    campaña A con dinero reservado para la B, dejando a la B sin fondos.
--
-- La idea de la corrección es una sola: el compromiso de una campaña no depende
-- de su estado, sino de lo que todavía se le debe.
--
--   * Campaña ACTIVA  -> comprometido = presupuesto - pagado
--   * Campaña FINAL   -> comprometido = suma de sus pagos PENDIENTES
--
-- Con eso, cerrar libera únicamente el sobrante real y lo adeudado permanece
-- reservado hasta liquidarse. Decisión de negocio confirmada: el sobrante de
-- una campaña cerrada vuelve a saldo libre del estudio.
-- =====================================================================

-- Compromiso vigente por campaña, independiente del estado.
CREATE OR REPLACE VIEW v_campaign_compromiso AS
SELECT c.id AS campaign_id,
       CASE WHEN s.computa_garantia = TRUE
            THEN GREATEST(c.presupuesto - c.pagado, 0)
            ELSE COALESCE((SELECT SUM(p.total)
                             FROM payment p
                             JOIN cat_payment_state ps ON ps.id = p.payment_state_id
                            WHERE p.campaign_id = c.id AND ps.codigo = 'PENDIENTE'), 0)
       END AS comprometido
  FROM campaign c
  JOIN cat_campaign_state s ON s.id = c.campaign_state_id;

-- La garantía ahora suma el compromiso real, no solo el de las campañas activas.
CREATE OR REPLACE VIEW v_wallet_summary AS
SELECT w.saldo_total,
       w.total_depositado,
       COALESCE((SELECT SUM(comprometido) FROM v_campaign_compromiso), 0) AS en_garantia,
       w.saldo_total
         - COALESCE((SELECT SUM(comprometido) FROM v_campaign_compromiso), 0) AS monto_libre
FROM business_wallet w WHERE w.id = 1;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Cierre / cancelación: se libera solo el sobrante que ya no se debe.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_campaign_finalizar$$

CREATE PROCEDURE sp_campaign_finalizar(IN p_campaign_id BIGINT, IN p_estado_codigo VARCHAR(30), IN p_user_id BIGINT)
BEGIN
    DECLARE v_presupuesto DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);
    DECLARE v_pendiente_total DECIMAL(12,2);
    DECLARE v_liberado DECIMAL(12,2);
    DECLARE v_estado TINYINT;
    DECLARE v_tipo TINYINT;

    SELECT id INTO v_estado FROM cat_campaign_state WHERE codigo = p_estado_codigo AND es_final = TRUE;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado final inválido';
    END IF;

    START TRANSACTION;
        SELECT id FROM business_wallet WHERE id=1 FOR UPDATE;
        SELECT presupuesto, pagado INTO v_presupuesto, v_pagado
          FROM campaign WHERE id = p_campaign_id FOR UPDATE;

        SELECT COALESCE(SUM(p.total), 0) INTO v_pendiente_total
          FROM payment p
          JOIN cat_payment_state ps ON ps.id = p.payment_state_id
         WHERE p.campaign_id = p_campaign_id AND ps.codigo = 'PENDIENTE';

        SELECT id INTO v_tipo FROM cat_movement_type WHERE codigo='LIBERACION_GARANTIA';

        UPDATE campaign SET campaign_state_id = v_estado, version = version + 1 WHERE id = p_campaign_id;

        -- Lo adeudado NO se libera: sigue comprometido por v_campaign_compromiso.
        SET v_liberado = GREATEST(v_presupuesto - v_pagado - v_pendiente_total, 0);

        IF v_liberado > 0 THEN
            INSERT INTO wallet_movement (movement_type_id, monto, campaign_id, nota, hecho_por)
            VALUES (v_tipo, v_liberado, p_campaign_id,
                    CONCAT('Liberación de garantía no gastada. Quedan pendientes por ',
                           FORMAT(v_pendiente_total, 2)),
                    p_user_id);
        END IF;
    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- Pago: se valida contra lo disponible, no contra el saldo bruto.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_payment_marcar_pagado$$

CREATE PROCEDURE sp_payment_marcar_pagado(
    IN p_payment_id BIGINT, IN p_referencia VARCHAR(200), IN p_user_id BIGINT)
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_campaign BIGINT;
    DECLARE v_saldo DECIMAL(12,2);
    DECLARE v_otras DECIMAL(12,2);
    DECLARE v_disponible DECIMAL(12,2);
    DECLARE v_pagado TINYINT;
    DECLARE v_tipo TINYINT;
    DECLARE v_estado_actual TINYINT;

    START TRANSACTION;
        SELECT saldo_total INTO v_saldo FROM business_wallet WHERE id=1 FOR UPDATE;
        SELECT total, campaign_id, payment_state_id
          INTO v_total, v_campaign, v_estado_actual
          FROM payment WHERE id = p_payment_id FOR UPDATE;

        SELECT id INTO v_pagado FROM cat_payment_state WHERE codigo='PAGADO';

        IF v_estado_actual = v_pagado THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pago ya estaba marcado como pagado';
        END IF;

        -- Disponible = saldo menos lo comprometido con las DEMÁS campañas.
        -- (El compromiso de esta campaña es justamente lo que estamos liquidando.)
        SELECT COALESCE(SUM(comprometido), 0) INTO v_otras
          FROM v_campaign_compromiso WHERE campaign_id <> v_campaign;
        SET v_disponible = v_saldo - v_otras;

        IF v_total > v_disponible THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
                'Saldo insuficiente: el resto está comprometido en otras campañas';
        END IF;

        SELECT id INTO v_tipo FROM cat_movement_type WHERE codigo='PAGO_EDITOR';

        UPDATE business_wallet SET saldo_total = saldo_total - v_total WHERE id = 1;
        UPDATE campaign SET pagado = pagado + v_total, version = version + 1 WHERE id = v_campaign;
        UPDATE payment
           SET payment_state_id = v_pagado, fecha_pago = NOW(6),
               referencia = p_referencia, marcado_por = p_user_id
         WHERE id = p_payment_id;

        INSERT INTO wallet_movement (movement_type_id, monto, campaign_id, nota, hecho_por)
        VALUES (v_tipo, v_total, v_campaign, CONCAT('Pago a editor. Ref: ', COALESCE(p_referencia,'')), p_user_id);
    COMMIT;
END$$

DELIMITER ;
