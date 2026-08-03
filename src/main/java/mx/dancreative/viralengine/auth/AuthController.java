package mx.dancreative.viralengine.auth;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import mx.dancreative.viralengine.domain.User;
import mx.dancreative.viralengine.repo.UserRepository;
import mx.dancreative.viralengine.security.JwtService;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.security.Principal;

@RestController
@RequestMapping("/auth")
public class AuthController {

    public record LoginRequest(@Email @NotBlank String email, @NotBlank String password) {}
    public record LoginResponse(String token, Long id, String nombre, String role) {}
    public record MeResponse(Long id, String nombre, String email, String role, String correoPaypal) {}

    private final UserRepository users;
    private final PasswordEncoder encoder;
    private final JwtService jwt;
    private final LoginRateLimiter limiter;
    private final JdbcTemplate jdbc;

    public AuthController(UserRepository users, PasswordEncoder encoder, JwtService jwt,
                          LoginRateLimiter limiter, JdbcTemplate jdbc) {
        this.users = users; this.encoder = encoder; this.jwt = jwt;
        this.limiter = limiter; this.jdbc = jdbc;
    }

    @PostMapping("/login")
    public LoginResponse login(@Valid @RequestBody LoginRequest req, HttpServletRequest http) {
        String ip = ip(http);
        String clave = req.email().toLowerCase() + "|" + ip;
        limiter.verificar(clave);

        User u = users.findByEmail(req.email()).orElse(null);

        if (u == null || !encoder.matches(req.password(), u.getPasswordHash())) {
            limiter.registrarFallo(clave);
            registrar(u == null ? null : u.getId(), "LOGIN_FALLIDO",
                      "Credenciales inválidas para " + req.email() + " desde " + ip);
            // mismo mensaje para usuario inexistente y contraseña incorrecta:
            // no revelamos qué correos están registrados
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Credenciales inválidas");
        }

        if (!"ACTIVO".equals(u.getUserState().getCodigo())) {
            registrar(u.getId(), "LOGIN_BLOQUEADO", "Cuenta " + u.getUserState().getCodigo());
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                "Tu cuenta está " + u.getUserState().getCodigo().toLowerCase() + ".");
        }

        limiter.limpiar(clave);
        registrar(u.getId(), "LOGIN", "Inicio de sesión desde " + ip);
        return new LoginResponse(jwt.generate(u), u.getId(), u.getNombre(), u.getUserType().getCodigo());
    }

    @GetMapping("/me")
    public MeResponse me(Principal principal) {
        User u = users.findByEmail(principal.getName())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Sesión inválida"));
        return new MeResponse(u.getId(), u.getNombre(), u.getEmail(),
                u.getUserType().getCodigo(), u.getCorreoPaypal());
    }

    private String ip(HttpServletRequest req) {
        String fwd = req.getHeader("X-Forwarded-For");
        return (fwd != null && !fwd.isBlank()) ? fwd.split(",")[0].trim() : req.getRemoteAddr();
    }

    private void registrar(Long userId, String accion, String detalle) {
        try {
            jdbc.update("INSERT INTO audit_log (user_id, accion, detalle) VALUES (?, ?, ?)",
                        userId, accion, detalle);
        } catch (Exception ignore) { /* la bitácora nunca debe bloquear el login */ }
    }
}
