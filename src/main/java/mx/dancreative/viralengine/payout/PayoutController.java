package mx.dancreative.viralengine.payout;

import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import mx.dancreative.viralengine.wallet.WalletService;

import java.util.List;
import java.util.Map;

@RestController
@PreAuthorize("hasRole('ADMIN')")
public class PayoutController {

    private final JdbcTemplate jdbc;

    public PayoutController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    private Long uid() {
        return (Long) SecurityContextHolder.getContext().getAuthentication().getDetails();
    }

    /** Calcula (o recalcula) los pagos de una campaña. Los ya PAGADOS no se tocan. */
    @PostMapping("/campaigns/{id}/compute-payouts")
    public Map<String, Object> compute(@PathVariable long id) {
        try {
            jdbc.update("CALL sp_calcular_pagos(?, ?)", id, uid());
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
        return jdbc.queryForMap(
            "SELECT * FROM payout_run WHERE campaign_id = ? ORDER BY id DESC LIMIT 1", id);
    }

    @GetMapping("/payments")
    public List<Map<String, Object>> payments(@RequestParam(required = false) Long campaign,
                                              @RequestParam(required = false) String quincena) {
        return jdbc.queryForList("""
           SELECT p.id, p.campaign_id, p.editor_id, c.nombre AS campana, u.nombre AS editor,
                   u.correo_paypal, p.pago_base, p.bono_escalon, p.bono_acumulado,
                   p.premio_1, p.total, s.codigo AS estado, p.quincena, p.referencia
              FROM payment p
              JOIN campaign c ON c.id = p.campaign_id
              JOIN users u    ON u.id = p.editor_id
              JOIN cat_payment_state s ON s.id = p.payment_state_id
             WHERE (? IS NULL OR p.campaign_id = ?)
               AND (? IS NULL OR p.quincena = ?)
             ORDER BY c.id, u.nombre""",
            campaign, campaign, quincena, quincena);
    }

    @PostMapping("/payments/{id}/mark-paid")
    public void markPaid(@PathVariable long id, @RequestBody Map<String, String> body) {
        try {
            jdbc.update("CALL sp_payment_marcar_pagado(?, ?, ?)",
                    id, body.getOrDefault("referencia", null), uid());
        } catch (DataAccessException e) { throw WalletService.traducir(e); }
    }
}
