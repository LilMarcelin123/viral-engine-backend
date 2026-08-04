-- =====================================================================
-- V14 — clip_publication.created_at
--
-- fn_publicaciones_hoy_cuenta y fn_publicaciones_hoy_editor cuentan las
-- publicaciones del día con DATE(created_at) = CURDATE(), pero la tabla
-- clip_publication nunca tuvo esa columna: solo `updated_at`, que es la marca
-- del último scrapeo y además es NULL hasta que se scrapea.
--
-- Consecuencia: sp_clip_publicacion_alta fallaba SIEMPRE con
-- "Unknown column 'created_at' in 'where clause'", así que registrar la
-- publicación de un clip era imposible y los topes diarios nunca se aplicaron.
--
-- Se agrega la columna con default. Las publicaciones que ya existieran
-- (si las hay) quedan fechadas al momento de la migración; no hay forma de
-- recuperar su fecha real y son de prueba.
--
-- Las funciones no se tocan: escritas como están, funcionan en cuanto la
-- columna existe.
-- =====================================================================

ALTER TABLE clip_publication
    ADD COLUMN created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) AFTER likes;

-- Los topes diarios filtran por cuenta y fecha en cada alta.
CREATE INDEX idx_pub_cuenta_fecha ON clip_publication (editor_account_id, created_at);
