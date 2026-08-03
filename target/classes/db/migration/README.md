Coloca aqui V1__catalogos_y_esquema.sql ... V5__procedimientos_operativos.sql
para que Flyway los aplique en ambientes nuevos (Railway).
En tu base local ya los corriste a mano: baseline-version=5 hace que Flyway
no los repita y solo aplique migraciones nuevas (V6 en adelante).
NOTA: Flyway maneja DELIMITER distinto a Workbench; los procedimientos van
sin DELIMITER usando un solo statement por archivo o config de separador.
