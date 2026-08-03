package mx.dancreative.viralengine.wallet;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * Patrón de la capa de servicio: la lógica de dinero vive en los
 * procedimientos de MySQL (transaccionales, con bloqueo de fila).
 * Spring solo los invoca y traduce los SIGNAL a errores HTTP.
 */
@Service
public class WalletService {

    private final JdbcTemplate jdbc;

    public WalletService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public Map<String, Object> resumen() {
        return jdbc.queryForMap("""
            SELECT s.saldo_total,
                   s.total_depositado,
                   s.en_garantia,
                   s.en_garantia AS monto_en_garantia,
                   s.monto_libre,
                   COALESCE((SELECT SUM(m.monto) FROM wallet_movement m
                              JOIN cat_movement_type t ON t.id = m.movement_type_id
                             WHERE t.codigo = 'PAGO_EDITOR'
                               AND m.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)), 0)
                   AS gastado_30_dias
              FROM v_wallet_summary s""");
    }

    public List<Map<String, Object>> movimientos(int limit) {
        return jdbc.queryForList("""
            SELECT m.id, t.codigo AS tipo, m.monto, m.campaign_id, m.nota, m.created_at
              FROM wallet_movement m
              JOIN cat_movement_type t ON t.id = m.movement_type_id
             ORDER BY m.created_at DESC LIMIT ?""", limit);
    }

    public void depositar(BigDecimal monto, Long adminId, String nota) {
        try {
            jdbc.update("CALL sp_wallet_deposito(?, ?, ?)", monto, adminId, nota);
        } catch (DataAccessException e) {
            throw traducir(e);
        }
    }

    /** Los SIGNAL 45000 de MySQL llegan como mensaje de negocio: se exponen como 422. */
    public static ResponseStatusException traducir(DataAccessException e) {
        String msg = e.getMostSpecificCause().getMessage();
        return new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, msg);
    }
}
