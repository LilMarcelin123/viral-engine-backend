package mx.dancreative.viralengine.config;

import mx.dancreative.viralengine.security.JwtAuthFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final String corsOrigins;

    public SecurityConfig(@Value("${app.cors.origins}") String corsOrigins) {
        this.corsOrigins = corsOrigins;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http, JwtAuthFilter jwt) throws Exception {
        http.csrf(csrf -> csrf.disable())
            .cors(c -> {})
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(HttpMethod.POST, "/auth/login").permitAll()
                // los archivos se sirven sin token para que carguen en <img>;
                // SUBIR sí requiere sesión (lo protege @PreAuthorize del controlador)
                .requestMatchers(HttpMethod.GET, "/files/**").permitAll()
                .requestMatchers("/error").permitAll()
                .requestMatchers("/actuator/health").permitAll()   // healthcheck de Railway
                .anyRequest().authenticated())
            .addFilterBefore(jwt, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration cfg = new CorsConfiguration();
        cfg.setAllowedOrigins(Arrays.stream(corsOrigins.split(","))
                                    .map(String::trim).filter(s -> !s.isEmpty()).toList());
        cfg.setAllowedMethods(List.of("GET","POST","PUT","PATCH","DELETE","OPTIONS"));
        cfg.setAllowedHeaders(List.of("*"));
        UrlBasedCorsConfigurationSource src = new UrlBasedCorsConfigurationSource();
        src.registerCorsConfiguration("/**", cfg);
        return src;
    }

    /** Evita el usuario/contraseña por defecto de Spring: aquí autentica el filtro JWT. */
    @Bean
    public UserDetailsService userDetailsService() { return new InMemoryUserDetailsManager(); }
}
