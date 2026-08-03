package mx.dancreative.viralengine.wallet;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/wallet")
@PreAuthorize("hasRole('ADMIN')")           // toda la billetera es solo admin
public class WalletController {

    public record DepositRequest(@NotNull @DecimalMin(value = "0.01") BigDecimal monto, String nota) {}

    private final WalletService service;

    public WalletController(WalletService service) { this.service = service; }

    @GetMapping
    public Map<String, Object> resumen() { return service.resumen(); }

    @GetMapping("/movements")
    public List<Map<String, Object>> movimientos(@RequestParam(defaultValue = "50") int limit) {
        return service.movimientos(Math.min(limit, 200));
    }

    @PostMapping("/deposits")
    public Map<String, Object> depositar(@RequestBody DepositRequest req) {
        Long uid = (Long) SecurityContextHolder.getContext().getAuthentication().getDetails();
        service.depositar(req.monto(), uid, req.nota());
        return service.resumen();
    }
}
