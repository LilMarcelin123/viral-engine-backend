package mx.dancreative.viralengine.security;

import org.springframework.security.core.context.SecurityContextHolder;

public final class CurrentUser {
    private CurrentUser() {}
    /** uid que viaja en el JWT (claim "uid"). */
    public static Long id() {
        return (Long) SecurityContextHolder.getContext().getAuthentication().getDetails();
    }
}
