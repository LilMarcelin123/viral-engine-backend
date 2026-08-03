package mx.dancreative.viralengine.domain;

import jakarta.persistence.*;

@Entity @Table(name = "cat_user_type")
public class CatUserType {
	@Id private Byte id;
    @Column(nullable = false, unique = true) private String codigo;   // ADMIN / CLIENTE / EDITOR
    private String nombre;
    private Boolean activo;

    public Byte getId() { return id; }
    public String getCodigo() { return codigo; }
    public String getNombre() { return nombre; }
}
