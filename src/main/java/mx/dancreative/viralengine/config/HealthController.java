package mx.dancreative.viralengine.config;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

/** Endpoint público que Railway consulta para saber si la app está viva. */
@RestController
public class HealthController {
    @GetMapping("/actuator/health")
    public Map<String, String> health() { return Map.of("status", "UP"); }
}
