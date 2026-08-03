package mx.dancreative.viralengine.domain;

import jakarta.persistence.*;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity @Table(name = "users")
public class User {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false) private String nombre;
    @Column(nullable = false, unique = true) private String email;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "user_type_id")
    private CatUserType userType;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "user_state_id")
    private CatUserState userState;

    private String telefono;
    @Column(name = "fecha_nacimiento") private LocalDate fechaNacimiento;
    @Column(name = "correo_paypal")    private String correoPaypal;
    @Column(name = "tyc_version")      private String tycVersion;
    @Column(name = "tyc_aceptado_at")  private LocalDateTime tycAceptadoAt;
    @Column(name = "privacidad_aceptada_at") private LocalDateTime privacidadAceptadaAt;
    @Column(name = "created_at", insertable = false, updatable = false)
    private LocalDateTime createdAt;

    public Long getId() { return id; }
    public String getNombre() { return nombre; }
    public String getEmail() { return email; }
    public String getPasswordHash() { return passwordHash; }
    public CatUserType getUserType() { return userType; }
    public CatUserState getUserState() { return userState; }
    public String getCorreoPaypal() { return correoPaypal; }

    public void setNombre(String v) { this.nombre = v; }
    public void setEmail(String v) { this.email = v; }
    public void setPasswordHash(String v) { this.passwordHash = v; }
    public void setUserType(CatUserType v) { this.userType = v; }
    public void setUserState(CatUserState v) { this.userState = v; }
    public void setCorreoPaypal(String v) { this.correoPaypal = v; }
}
