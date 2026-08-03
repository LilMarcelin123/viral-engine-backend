package mx.dancreative.viralengine.domain;

import jakarta.persistence.*;

@Entity @Table(name = "cat_user_state")
public class CatUserState {
    @Id private Byte id;
    @Column(nullable = false, unique = true) private String codigo;   // ACTIVO / SUSPENDIDO / REMOVIDO
    private String nombre;

    public Byte getId() { return id; }
    public String getCodigo() { return codigo; }
}
