-- =====================================================================
-- V19 — Documentos legales (reempaque idempotente de la antigua V6).
--
-- POR QUÉ EXISTE ESTE ARCHIVO:
-- V6, V7 y V8 se cargaron a mano por el túnel y nunca entraron al repositorio.
-- En producción no se nota porque Flyway tiene baseline-version: 5 y da por
-- aplicado todo lo anterior. Pero una base LIMPIA creada desde el repo saldría
-- sin estas tablas, y el fallo no aparece al migrar —Flyway reporta éxito—
-- sino cuando el primer usuario llega a la pantalla de aceptación de términos
-- y se queda atorado ahí, porque bloquea el acceso a toda la aplicación.
--
-- POR QUÉ NO SE LLAMA V6:
-- Flyway valida al arrancar. Un archivo V6 con V18 ya aplicada haría fallar el
-- arranque con "Detected resolved migration not applied to database". Va como
-- V19 para que corra después de todo lo existente.
--
-- POR QUÉ ES IDEMPOTENTE:
-- En producción estas tablas YA existen con sus textos cargados. Con
-- IF NOT EXISTS e INSERT IGNORE, aquí no hace nada; en una base limpia deja
-- el esquema completo. Las tres tablas tienen clave única, así que IGNORE
-- discrimina bien y no duplica documentos.
-- =====================================================================

-- =====================================================================
-- VIRAL ENGINE — V6: Documentos legales y aceptación de usuarios
-- Cumple el requisito de "Cambios finales":
--   "Añadir aviso de privacidad y que acepten el contrato al darse de alta."
-- =====================================================================

CREATE TABLE IF NOT EXISTS cat_legal_type (
    id     TINYINT     NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(30) NOT NULL,
    nombre VARCHAR(120) NOT NULL,
    PRIMARY KEY (id), UNIQUE KEY uq_clt_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Los textos viven en la BD para poder actualizarlos sin desplegar código.
CREATE TABLE IF NOT EXISTS legal_document (
    id            BIGINT      NOT NULL AUTO_INCREMENT,
    legal_type_id TINYINT     NOT NULL,
    version       VARCHAR(20) NOT NULL,
    titulo        VARCHAR(200) NOT NULL,
    contenido     MEDIUMTEXT  NOT NULL,
    vigente       BOOLEAN     NOT NULL DEFAULT TRUE,
    publicado_at  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_legal (legal_type_id, version),
    KEY idx_legal_vigente (legal_type_id, vigente),
    CONSTRAINT fk_ld_type FOREIGN KEY (legal_type_id) REFERENCES cat_legal_type (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bitácora de aceptación: queda constancia de qué versión aceptó cada quien,
-- cuándo, desde qué IP y con qué navegador (evidencia legal).
CREATE TABLE IF NOT EXISTS legal_acceptance (
    id                BIGINT       NOT NULL AUTO_INCREMENT,
    user_id           BIGINT       NOT NULL,
    legal_document_id BIGINT       NOT NULL,
    aceptado_at       DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    ip                VARCHAR(45)  NULL,
    user_agent        VARCHAR(255) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_acceptance (user_id, legal_document_id),
    CONSTRAINT fk_la_user FOREIGN KEY (user_id)           REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_la_doc  FOREIGN KEY (legal_document_id) REFERENCES legal_document (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO cat_legal_type (codigo, nombre) VALUES
    ('TYC_EDITOR','Términos y Condiciones — Editores'),
    ('TYC_CLIENTE','Términos y Condiciones — Clientes'),
    ('PRIVACIDAD','Aviso de Privacidad');

INSERT IGNORE INTO legal_document (legal_type_id, version, titulo, contenido)
SELECT id, '2026-07-20', 'Términos y Condiciones de Uso — Editores', 'DAN CREATIVE · VIRAL ENGINE
TÉRMINOS Y CONDICIONES DE USO — EDITORES
Plataforma Viral Engine
Última actualización: 20 de julio de 2026
Estos Términos y Condiciones de Uso (los "Términos") regulan el acceso y uso de la plataforma Viral Engine,
operada por [RAZÓN SOCIAL Dan Creative S.A. de C.V.] (en adelante "Viral Engine" o "Dan Creative"), por
parte de las personas que se registran como editores de contenido (en adelante "el Editor" o "tú").
Al crear una cuenta, marcar la casilla de aceptación, o confirmar tu participación en cualquier campaña
dentro de la plataforma, aceptas estos Términos en su totalidad. Si no estás de acuerdo, no debes registrarte ni
utilizar la plataforma.
1. Naturaleza de la relación
El Editor participa en Viral Engine como prestador de servicios independiente a través de la plataforma. El uso de la
plataforma no constituye, bajo ninguna circunstancia, una relación laboral, de subordinación, agencia o sociedad
entre el Editor y Dan Creative. El Editor no es empleado de Dan Creative ni de Viral Engine y no tiene derecho a
prestaciones laborales, seguridad social, ni beneficios distintos a lo expresamente pactado en estos Términos.
El Editor conserva libertad para prestar servicios similares a terceros y para rechazar la asignación de una campaña,
sujeto a las reglas de reasignación descritas en la Sección 6.
2. Cuenta y registro
• Ser mayor de 18 años de edad al momento del registro.
• Proporcionar información veraz, completa y actualizada al crear tu cuenta, incluyendo tus cuentas de TikTok,
Instagram y YouTube y tu método de pago.
• Registrar un máximo de 3 cuentas por plataforma (3 en TikTok, 3 en Instagram y 3 en YouTube), es decir,
hasta 9 cuentas en total por Editor. Dan Creative podrá ajustar este límite por Editor o por campaña,
notificándolo a través de la plataforma.
• Mantener la confidencialidad de tus credenciales de acceso; eres responsable de toda actividad realizada desde
tu cuenta.
• Solo se permite una cuenta de editor por persona, salvo autorización expresa de Dan Creative.
Dan Creative se reserva el derecho de admitir, rechazar, suspender o cerrar la cuenta de cualquier editor a su
discreción razonable, incluyendo por incumplimiento de estos Términos.
3. Cómo se financia y se paga el trabajo
Por cada video vendido dentro de una campaña, Viral Engine aparta $30.00 MXN destinados a editores: $10.00
MXN como pago base garantizado y $20.00 MXN que se destinan a una bolsa de bonos. El monto total de la bolsa
de bonos de cada campaña es fijo, se calcula por adelantado y es, por diseño, imposible de rebasar. Esta bolsa se
divide en tres sub-bolsas independientes, correspondientes a los tres tipos de bono descritos en 3.2, 3.3 y 3.4.
3.1 Pago base — $10 MXN por clip aprobado. Garantizado: si el clip aprueba el control de calidad (QA), se cobra
sin excepción, incluso si dicho clip es excluido posteriormente de la bolsa de bonos conforme a la Sección 5. Se
liquida en el corte quincenal.
3.2 Bonos por clip (60% de la bolsa de bonos). Cada clip que subas y que sea aprobado por QA participa en el
reparto de esta sub-bolsa según el total de vistas que acumule, sumando TikTok, Instagram y YouTube. Entre más
vistas logre tu clip, más alto es el escalón de bono al que puede acceder: el bono comienza en $10 MXN al llegar a
las primeras 5,000 vistas, sube a $25 MXN a partir de 10,000 vistas, a $75 MXN a partir de 50,000, a $200 MXN a
partir de 100,000, a $600 MXN a partir de 500,000, y llega hasta $1,500 MXN si tu clip alcanza el millón de vistas.
Siempre se considera el escalón más alto que tu clip haya alcanzado, no la suma de los escalones anteriores.
3.3 Bono por acumulado (25% de la bolsa de bonos). Además del bono por clip individual, se premia la
consistencia: se suman las vistas de todos tus clips aprobados y no excluidos dentro de una misma campaña. Al
llegar a 50,000 vistas acumuladas se accede a $30 MXN adicionales, al llegar a 100,000 a $60 MXN, y al alcanzar
200,000 el bono sube a $120 MXN. Este bono se puede alcanzar con trabajo constante y bien hecho, sin necesidad
de que un solo clip se vuelva viral.
3.4 Premio al clip #1 (15% de la bolsa de bonos). $300 MXN para el clip con más vistas de toda la campaña.
Existe un único ganador por campaña, visible en el leaderboard de la plataforma durante la vigencia de esta.
3.5 Regla de participación y límite de la bolsa. Todo clip que alcance uno de los escalones descritos en 3.2, 3.3 o
3.4 participa y tiene garantizado un pago dentro de la sub-bolsa correspondiente: el acceso a la bolsa de bonos no
depende del orden de llegada ni queda a discreción de Dan Creative. Sin embargo, como cada sub-bolsa tiene un
monto máximo fijo calculado por adelantado, si la suma de los pagos que corresponderían a todos los clips
participantes de un mismo escalón excede lo disponible en la sub-bolsa, dichos pagos se ajustan proporcionalmente
entre todos los clips de ese escalón, de manera que todo Editor que haya calificado reciba un pago, aunque el monto
pueda ser menor al escalón nominal indicado. Por esta razón, Viral Engine comunica sus bonos como "hasta $X en
bonos" y no como un monto fijo garantizado en su totalidad para todos los participantes.
En términos generales: quien cumple con clips aprobados asegura su pago base; quien mantiene consistencia durante
toda la campaña accede también al bono por acumulado; y quien logra uno o varios clips destacados puede
multiplicar sus ingresos gracias a los bonos por escalón y al premio al clip #1 — siempre sujeto al límite y a la regla
de proporcionalidad descritos en 3.5.
4. Pagos internacionales y obligaciones fiscales
Dado que la comunidad de editores de Viral Engine incluye personas residentes en distintos países, los pagos se
realizan mediante PayPal u otro medio de pago electrónico equivalente habilitado en la plataforma, en la moneda y
al tipo de cambio vigente al momento de la transacción.
• El Editor es el único responsable de declarar y pagar los impuestos, contribuciones o cargas fiscales que
correspondan conforme a las leyes de su país de residencia.
• Dan Creative no retiene impuestos sobre los pagos realizados a Editores, salvo que la ley aplicable lo exija
expresamente.
• Los costos, comisiones o pérdidas cambiarias derivadas del método de pago elegido corren por cuenta del
Editor.
• Es responsabilidad del Editor mantener actualizada y correcta su información de pago dentro de la plataforma;
Dan Creative no será responsable por pagos enviados a datos erróneos proporcionados por el Editor.
5. Control de calidad y reglas de medición
• Las vistas de cada clip (TikTok + Instagram + YouTube) se congelan a los 14 días naturales de su publicación.
• Solo cuentan para efectos de pago los clips aprobados por control de calidad (QA) y publicados en cuentas de
la red autorizada por Viral Engine.
• El pago base se liquida en el corte quincenal; los bonos se liquidan en la quincena siguiente al cierre de
medición de cada campaña.
• Vistas infladas, compradas o generadas de forma artificial resultan en la exclusión de dicho clip de la bolsa
de bonos (Sección 3) y en la aplicación de un strike al Editor. Esta exclusión no afecta el pago base del clip: si
éste fue aprobado por QA, se liquida conforme a lo dispuesto en 3.1.
• Acumular tres (3) strikes resulta en la remoción definitiva del Editor de la plataforma.
6. Reparto y reasignación del trabajo
Al abrirse una campaña dentro de la plataforma, el Editor cuenta con 24 horas para confirmar su participación. Los
videos se reparten de forma equitativa entre los editores confirmados, sujeto a un tope (cap) por editor determinado
según sus cuentas y el tamaño de la campaña, con el fin de proteger la salud de las cuentas involucradas.
Si el Editor no confirma su participación dentro de las 24 horas, dichos clips pasan a una bolsa de reasignación
dentro de la plataforma. Otros editores pueden reclamar estos clips como trabajo adicional, siempre que mantengan
una tasa de aprobación en QA igual o mayor al 85%.
6.1 Límites de publicación. Cada campaña define, al momento de su apertura, la cantidad total de clips requeridos
para la campaña. Esta información es visible para el Editor en la pantalla de inscripción de cada campaña, antes de
confirmar su participación. Adicionalmente, el Editor puede subir un máximo de 5 clips por cuenta y por plataforma
(TikTok, Instagram o YouTube) por día natural, con un límite total de 15 clips por Editor por día, considerando todas
sus cuentas y plataformas.
7. Propiedad intelectual y licencia de uso
7.1 Titularidad del Editor. El Editor conserva la titularidad y los derechos de autor sobre la edición (el "clip") que
produce, incluyendo el trabajo creativo de edición, cortes, ritmo y efectos aplicados sobre los assets, música y brief
proporcionados a través de la plataforma.
7.2 Licencia otorgada. Al entregar y publicar un clip como parte de una campaña, el Editor otorga a Dan Creative,
a Viral Engine y al cliente de la campaña correspondiente una licencia no exclusiva para exhibir, publicar y
mantener dicho clip visible en las cuentas autorizadas de la campaña.
7.3 Periodo mínimo de permanencia. Ni Dan Creative ni el cliente podrán eliminar, ocultar o alterar de forma
sustancial el clip publicado durante un periodo mínimo de tres (3) meses contados a partir de su fecha de
publicación, salvo (a) solicitud expresa del propio Editor, (b) causa de moderación o control de calidad debidamente
justificada, o (c) requerimiento legal de autoridad competente.
7.4 Uso posterior al periodo mínimo. Transcurrido el periodo mínimo de tres meses, cualquiera de las partes podrá
solicitar la remoción del clip de las cuentas de la campaña, salvo que se acuerde una vigencia distinta.
7.5 Uso interno. El Editor autoriza a Dan Creative a utilizar las métricas del clip (vistas, ranking) y una referencia
del propio clip para fines de leaderboard, portafolio y promoción de la plataforma Viral Engine.
8. Uso de cuentas propias del editor
El Editor publica los clips en cuentas de redes sociales de su propiedad o gestión. Dan Creative no garantiza que
dichas cuentas estarán libres de penalizaciones, restricciones o suspensiones por parte de TikTok, Instagram,
YouTube u otras plataformas, y no será responsable por dichas medidas ni por la pérdida de vistas, alcance o
ingresos derivada de ellas. El Editor es responsable de mantener sus cuentas en cumplimiento con los términos de
servicio de cada plataforma.
9. Confidencialidad y conducta
El Editor se obliga a mantener confidencial cualquier música inédita, brief, estrategia de campaña, información de
clientes o cualquier otro material no público que reciba a través de la plataforma. Asimismo, se compromete a
mantener una conducta profesional y respetuosa dentro de los canales de comunicación de la comunidad,
absteniéndose de acoso, fraude, suplantación de identidad o cualquier conducta que dañe la reputación de Dan
Creative, Viral Engine o de otros miembros de la comunidad.
10. Declaraciones y garantías del Editor
• Que la información proporcionada en tu registro es veraz y te pertenece.
• Que los clips que produces no incorporan material de terceros distinto al proporcionado por Dan Creative o el
cliente, salvo que cuentes con los derechos o licencias necesarios para usarlo.
• Que no utilizarás bots, granjas de clics, compra de vistas/seguidores, ni ningún otro medio artificial para inflar
métricas.
• Que no te encuentras en ninguna lista de sanciones, restricciones comerciales o similares emitida por
autoridades de México, Estados Unidos, la Unión Europea o la ONU.
• Que no suplantarás la identidad de otra persona ni proporcionarás información falsa sobre tus cuentas o tu
identidad.
11. Indemnización
El Editor se obliga a sacar en paz y a salvo, defender e indemnizar a Dan Creative, Viral Engine, sus clientes,
directivos, empleados y colaboradores, frente a cualquier reclamación, sanción, daño o gasto (incluyendo honorarios
legales razonables) que derive de: (a) el incumplimiento de estos Términos por parte del Editor; (b) el uso indebido
de la plataforma o de las cuentas del Editor; (c) contenido subido por el Editor que infrinja derechos de terceros; o
(d) el incumplimiento de las obligaciones fiscales del Editor en su país de residencia.
12. Disponibilidad de la plataforma
La plataforma se proporciona "tal cual" y "según disponibilidad". Dan Creative no garantiza que el acceso a la
plataforma será ininterrumpido, libre de errores, o que estará disponible en todo momento, y no será responsable por
fallas técnicas, caídas del sistema, pérdida de información, o interrupciones causadas por terceros (incluyendo
TikTok, Instagram, proveedores de pago, o proveedores de infraestructura).
13. No evasión de la plataforma
Durante su participación en Viral Engine y hasta doce (12) meses después de terminada su relación con la
plataforma, el Editor se obliga a no contactar, solicitar o acordar directamente con clientes de Viral Engine la
prestación de servicios similares a los de una campaña, con el fin de evadir el uso de la plataforma y las condiciones
aquí pactadas, salvo autorización previa y por escrito de Dan Creative.
14. Caso fortuito o fuerza mayor
Ninguna de las partes será responsable por el incumplimiento o retraso en sus obligaciones derivado de causas fuera
de su control razonable, incluyendo fallas de las plataformas de TikTok, Instagram o YouTube, desastres naturales,
fallas masivas de internet o energía eléctrica, actos de autoridad, o cualquier otro caso fortuito o de fuerza mayor.
15. Privacidad de datos
El tratamiento de los datos personales del Editor se rige por el Aviso de Privacidad de Dan Creative, disponible en la
plataforma. Al registrarte, confirmas haberlo leído y aceptado.
16. Suspensión y cierre de cuenta
Dan Creative podrá suspender o cerrar la cuenta de un Editor en cualquier momento, con o sin causa, mediante aviso
a través de la plataforma o los canales oficiales. La suspensión o cierre no afecta el derecho del Editor a recibir los
pagos ya devengados por clips aprobados por QA previos a dicha fecha. La remoción por acumulación de tres
strikes se rige por lo dispuesto en la Sección 5.
17. Límite de responsabilidad
Dan Creative no garantiza un número específico de vistas, bonos, o ingresos totales para ningún Editor. Los
ejemplos de ganancias potenciales que Dan Creative pudiera compartir son ilustrativos y no constituyen una
promesa ni garantía de resultado. En la máxima medida permitida por la ley aplicable, la responsabilidad total de
Dan Creative frente al Editor por cualquier causa relacionada con la plataforma no excederá el monto de los pagos
efectivamente devengados por el Editor en los tres (3) meses previos al hecho que origine la reclamación. Dan
Creative no será responsable por daños indirectos, incidentales o consecuenciales.
18. Cesión
Dan Creative podrá ceder o transferir sus derechos y obligaciones bajo estos Términos, total o parcialmente,
incluyendo en el contexto de una fusión, adquisición o venta de activos. El Editor no podrá ceder sus derechos u
obligaciones sin el consentimiento previo y por escrito de Dan Creative.
19. Divisibilidad, renuncia y notificaciones
Si alguna disposición de estos Términos fuera declarada inválida o inaplicable por autoridad competente, dicha
disposición se ajustará al mínimo necesario para ser válida, y el resto de los Términos continuará en pleno vigor. El
hecho de que Dan Creative no ejerza un derecho previsto en estos Términos no implica una renuncia al mismo. Las
notificaciones oficiales entre las partes se realizarán a través de la plataforma o a los datos de contacto registrados en
la cuenta del Editor.
20. Modificaciones a los términos
Dan Creative podrá actualizar estos Términos en cualquier momento. Los cambios serán notificados a través de la
plataforma o los canales oficiales de la comunidad y entrarán en vigor a partir de su publicación. El uso continuado
de la plataforma después de dicha notificación constituye aceptación de los Términos actualizados.
21. Legislación aplicable y jurisdicción
Estos Términos se rigen por las leyes aplicables en la Ciudad de México, México. Para su interpretación y
cumplimiento, las partes se someten a los tribunales competentes de la Ciudad de México, renunciando a cualquier
otro fuero que pudiera corresponderles por razón de su domicilio presente o futuro, sin perjuicio de las disposiciones
imperativas de protección al consumidor que, en su caso, resulten aplicables en el país de residencia del Editor.
22. Aceptación
El registro como editor en la plataforma Viral Engine, la marca de la casilla de aceptación, o la confirmación de
participación en cualquier campaña, constituye la aceptación expresa y sin reservas de los presentes Términos y
Condiciones. Esta aceptación se realiza de forma digital y no requiere firma autógrafa.'
  FROM cat_legal_type WHERE codigo = 'TYC_EDITOR';

INSERT IGNORE INTO legal_document (legal_type_id, version, titulo, contenido)
SELECT id, '2026-07-20', 'Términos y Condiciones de Uso — Clientes', 'DAN CREATIVE · VIRAL ENGINE
TÉRMINOS Y CONDICIONES DE USO — CLIENTES
Plataforma Viral Engine (campañas self-service)
Última actualización: 20 de julio de 2026
Estos Términos y Condiciones de Uso (los "Términos") regulan el acceso y uso de la plataforma Viral Engine,
operada por [RAZÓN SOCIAL LEGAL — completar, ej. Dan Creative S.A. de C.V.] (en adelante "Viral
Engine" o "Dan Creative"), por parte de clientes que crean y gestionan sus propias campañas directamente dentro de
la plataforma (en adelante "el Cliente" o "tú").
Al crear una cuenta, marcar la casilla de aceptación, o inscribir una campaña dentro de la plataforma,
aceptas estos Términos en su totalidad. Si no estás de acuerdo, no debes registrarte ni utilizar la plataforma.
1. Alcance de estos Términos
Estos Términos aplican exclusivamente a clientes que inscriben y gestionan su campaña de forma autónoma
("self-service") a través de la plataforma Viral Engine. Los clientes cuya campaña es coordinada de forma
personalizada y directa por el equipo de Dan Creative, fuera de la plataforma, se rigen en su lugar por el Contrato de
Prestación de Servicios para Clientes Personalizados, el cual les será proporcionado por su ejecutivo de cuenta.
2. Cuenta y registro
• Registrarte con información veraz, completa y actualizada, incluyendo datos de contacto y facturación.
• Mantener la confidencialidad de tus credenciales de acceso; eres responsable de toda actividad realizada desde
tu cuenta.
• Contar con los derechos necesarios sobre la música, marca y demás materiales que subas a la plataforma para
tu campaña.
3. Cómo funciona una campaña dentro de la plataforma
Al inscribir una campaña, el Cliente selecciona un paquete de videos, sube la música, el brief creativo y los assets
necesarios, y confirma el pago correspondiente. Una vez confirmada, Viral Engine asigna automáticamente los clips
entre los editores disponibles de la comunidad y aplica el proceso de control de calidad (QA) sobre cada entrega.
Los clips se publican en las cuentas autorizadas de la campaña en TikTok, Instagram y YouTube, según lo definido
para cada campaña.
4. Reportes de campaña
El Cliente podrá consultar el avance de su campaña en tiempo real dentro de la plataforma Viral Engine (videos
publicados, vistas y cumplimiento de hitos). Al concluir la campaña, Viral Engine entregará un reporte final integral
con los resultados completos, enviado tanto por correo electrónico como disponible dentro de la plataforma.
5. Cómo se determina el precio de tu campaña
El precio de una campaña self-service depende de la cantidad de videos contratados y del paquete que selecciones.
Todos los precios se expresan en pesos mexicanos (MXN) más el Impuesto al Valor Agregado (IVA) que
corresponda conforme a la legislación fiscal aplicable. El precio vigente se muestra dentro de la plataforma al
momento de crear tu campaña, y es el que aplica al confirmarla. Para volúmenes que no correspondan a los paquetes
publicados en la plataforma, el Cliente puede solicitar una cotización personalizada con un ejecutivo de cuenta, en
cuyo caso puede aplicar el Contrato de Prestación de Servicios para Clientes Personalizados en lugar de estos
Términos.
6. Pago y facturación
El pago se realiza a través de los métodos habilitados en la plataforma al momento de confirmar el paquete
seleccionado, en pesos mexicanos (MXN) más el IVA correspondiente. Viral Engine emitirá la factura (invoice)
correspondiente conforme a los datos de facturación proporcionados por el Cliente. El incumplimiento de pago
podrá resultar en la suspensión o cancelación de la campaña, sin perjuicio de las cantidades ya devengadas por el
trabajo entregado.
7. Ausencia de garantía de resultados específicos
El Cliente reconoce y acepta que la naturaleza de las redes sociales y del contenido viral implica un componente de
incertidumbre inherente. Viral Engine ejecuta cada campaña con base en sus mejores esfuerzos, sistemas de
incentivos y estándares de control de calidad, pero no garantiza un número específico de vistas, alcance,
interacciones, seguidores, conversiones ni cualquier otro resultado de negocio. Cualquier ejemplo, proyección o
estimado mostrado en la plataforma es meramente ilustrativo y no constituye una promesa de resultado.
8. Propiedad intelectual
8.1 Activos del Cliente. La música, marca y demás activos que el Cliente suba a la plataforma permanecen en todo
momento bajo su titularidad. El Cliente otorga a Dan Creative y a los editores de la comunidad una licencia
temporal, no exclusiva, para utilizar dichos activos únicamente con el fin de producir y distribuir los clips de su
campaña.
8.2 Titularidad de los clips editados. Los clips son creados por editores independientes de la comunidad Viral
Engine, quienes conservan en todo momento la titularidad y los derechos de autor sobre el trabajo de edición; esta
titularidad nunca se transfiere al Cliente. El Cliente recibe únicamente una licencia limitada para que dichos clips
permanezcan publicados y visibles en las cuentas autorizadas de su campaña en TikTok, Instagram y YouTube,
durante la vigencia de la campaña y el periodo mínimo de permanencia descrito en 8.3. Esta licencia no incluye el
derecho de descargar, republicar en cuentas propias del Cliente o de terceros, utilizar en pauta publicitaria
(ads) fuera de las cuentas autorizadas de la campaña, ni explotar el clip de ninguna otra forma dentro o fuera
de la plataforma. Cualquier uso adicional del clip requiere la autorización expresa y por escrito del editor titular del
mismo.
8.3 Periodo mínimo de permanencia. El Cliente se obliga a no solicitar ni ejecutar la eliminación, ocultamiento o
alteración sustancial de un clip publicado durante un periodo mínimo de tres (3) meses contados a partir de su fecha
de publicación en las cuentas autorizadas de la campaña (TikTok, Instagram y YouTube), salvo causa de moderación
justificada o requerimiento legal de autoridad competente.
8.4 Uso posterior al periodo mínimo. Transcurrido el periodo mínimo de tres meses, el clip podrá ser eliminado de
las cuentas de la campaña, a solicitud del Cliente, del editor titular, o por decisión de Dan Creative, salvo que se
acuerde una vigencia distinta.
9. Declaraciones y garantías del Cliente
• Que cuentas con todos los derechos, licencias y autorizaciones necesarios sobre la música, marca, artista o
contenido que subas a la plataforma para tu campaña, incluyendo, en su caso, la autorización del titular de los
derechos de autor y conexos de la música utilizada.
• Que el uso de dicha música y demás materiales dentro de la campaña no infringe derechos de propiedad
intelectual, de imagen, o cualquier otro derecho de terceros.
• Que la información proporcionada en tu registro y facturación es veraz y completa.
• Que no utilizarás la plataforma para promover contenido ilegal, difamatorio, discriminatorio, o que infrinja
derechos de terceros.
• Que no te encuentras en ninguna lista de sanciones, restricciones comerciales o similares emitida por
autoridades de México, Estados Unidos, la Unión Europea o la ONU.
10. Indemnización
El Cliente se obliga a sacar en paz y a salvo, defender e indemnizar a Dan Creative, Viral Engine, los editores de la
comunidad, directivos, empleados y colaboradores, frente a cualquier reclamación, sanción, daño o gasto
(incluyendo honorarios legales razonables) que derive de: (a) el incumplimiento de estos Términos por parte del
Cliente; (b) reclamaciones de terceros relacionadas con la música, marca o materiales proporcionados por el Cliente,
incluyendo reclamaciones por infracción de derechos de autor; o (c) el uso indebido de la plataforma por parte del
Cliente.
11. Disponibilidad de la plataforma
La plataforma se proporciona "tal cual" y "según disponibilidad". Dan Creative no garantiza que el acceso a la
plataforma será ininterrumpido, libre de errores, o que estará disponible en todo momento, y no será responsable por
fallas técnicas, caídas del sistema, pérdida de información, o interrupciones causadas por terceros (incluyendo
TikTok, Instagram, YouTube, proveedores de pago, o proveedores de infraestructura).
12. No contratación directa de editores
Durante la vigencia de su campaña y hasta doce (12) meses después de concluida, el Cliente se obliga a no contactar,
contratar o acordar directamente con los editores de la comunidad Viral Engine la prestación de servicios similares a
los ofrecidos en la plataforma, con el fin de evadir el uso de la plataforma y las condiciones aquí pactadas, salvo
autorización previa y por escrito de Dan Creative.
13. Caso fortuito o fuerza mayor
Ninguna de las partes será responsable por el incumplimiento o retraso en sus obligaciones derivado de causas fuera
de su control razonable, incluyendo fallas de las plataformas de TikTok, Instagram o YouTube, desastres naturales,
fallas masivas de internet o energía eléctrica, actos de autoridad, o cualquier otro caso fortuito o de fuerza mayor.
14. Cancelaciones y reembolsos
• Si la campaña aún no ha iniciado producción (sin editores asignados ni clips en curso), el Cliente puede
cancelarla desde la plataforma y recibir reembolso, descontando cargos administrativos ya incurridos.
• Una vez iniciada la producción, las cantidades correspondientes a videos ya producidos, asignados o
aprobados por control de calidad no son reembolsables.
Nota de consistencia: la suspensión o cancelación de una campaña por falta de pago (Secciones 6 y 16) no exime
del periodo mínimo de permanencia pactado en 8.3 respecto de los clips ya publicados, ya que dicho compromiso se
asume frente al editor titular del clip, no solo frente al Cliente. Se sugiere validar este punto con el equipo legal
para dejarlo explícito antes de publicar.
15. Privacidad de datos
El tratamiento de los datos personales y de facturación del Cliente se rige por el Aviso de Privacidad de Dan
Creative, disponible en la plataforma. Al registrarte, confirmas haberlo leído y aceptado.
16. Suspensión y cierre de cuenta
Dan Creative podrá suspender o cancelar una campaña o cerrar la cuenta de un Cliente en caso de incumplimiento
de estos Términos, uso indebido de la plataforma, o falta de pago, sin perjuicio de las cantidades ya devengadas por
el trabajo entregado hasta ese momento. La suspensión o cancelación de una campaña por falta de pago no implica,
por sí sola, el retiro de los clips ya publicados, los cuales permanecen visibles conforme al periodo mínimo de
permanencia establecido en la Sección 8.3, salvo causa de moderación justificada o requerimiento legal de autoridad
competente.
17. Limitación de responsabilidad
En la máxima medida permitida por la ley aplicable, la responsabilidad total de Dan Creative frente al Cliente, por
cualquier causa relacionada con el uso de la plataforma, no excederá el monto efectivamente pagado por el Cliente
por la campaña en cuestión. Dan Creative no será responsable por daños indirectos, incidentales, consecuenciales, o
pérdida de utilidades u oportunidades de negocio del Cliente.
18. Cesión
Dan Creative podrá ceder o transferir sus derechos y obligaciones bajo estos Términos, total o parcialmente,
incluyendo en el contexto de una fusión, adquisición o venta de activos. El Cliente no podrá ceder sus derechos u
obligaciones sin el consentimiento previo y por escrito de Dan Creative.
19. Divisibilidad, renuncia y notificaciones
Si alguna disposición de estos Términos fuera declarada inválida o inaplicable por autoridad competente, dicha
disposición se ajustará al mínimo necesario para ser válida, y el resto de los Términos continuará en pleno vigor. El
hecho de que Dan Creative no ejerza un derecho previsto en estos Términos no implica una renuncia al mismo. Las
notificaciones oficiales entre las partes se realizarán a través de la plataforma o a los datos de contacto registrados en
la cuenta del Cliente.
20. Modificaciones a los términos
Dan Creative podrá actualizar estos Términos en cualquier momento. Los cambios serán notificados a través de la
plataforma y entrarán en vigor a partir de su publicación. El uso continuado de la plataforma después de dicha
notificación constituye aceptación de los Términos actualizados.
21. Legislación aplicable y jurisdicción
Estos Términos se rigen por las leyes aplicables en la Ciudad de México, México. Para su interpretación y
cumplimiento, las partes se someten a los tribunales competentes de la Ciudad de México, renunciando a cualquier
otro fuero que pudiera corresponderles por razón de su domicilio presente o futuro.
22. Aceptación
El registro como cliente en la plataforma Viral Engine, la marca de la casilla de aceptación, o la inscripción de una
campaña, constituye la aceptación expresa y sin reservas de los presentes Términos y Condiciones. Esta aceptación
se realiza de forma digital y no requiere firma autógrafa.'
  FROM cat_legal_type WHERE codigo = 'TYC_CLIENTE';

INSERT IGNORE INTO legal_document (legal_type_id, version, titulo, contenido)
SELECT id, '0.1-BORRADOR', 'Aviso de Privacidad', 'AVISO DE PRIVACIDAD — VIRAL ENGINE
[PENDIENTE DE REDACCIÓN LEGAL]

Este texto es un marcador temporal. Debe ser reemplazado por el Aviso de
Privacidad definitivo elaborado conforme a la Ley Federal de Protección de
Datos Personales en Posesión de los Particulares (LFPDPPP) de México.

El aviso definitivo debe incluir, como mínimo:

1. Identidad y domicilio del responsable (Dan Creative S.A. de C.V.).
2. Datos personales que se recaban: nombre, correo electrónico, teléfono,
   fecha de nacimiento, cuentas de redes sociales y datos de pago (PayPal).
3. Finalidades del tratamiento: gestión de campañas, control de calidad,
   cálculo y dispersión de pagos, y comunicación operativa.
4. Finalidades secundarias, si las hubiera, y forma de manifestar negativa.
5. Transferencias de datos a terceros, si aplica.
6. Medios para ejercer los derechos ARCO (acceso, rectificación,
   cancelación y oposición) y el correo de contacto para ello.
7. Procedimiento para revocar el consentimiento.
8. Uso de cookies o tecnologías de rastreo, si aplica.
9. Procedimiento de notificación de cambios al aviso.

Para actualizar este texto: edita el registro correspondiente en la tabla
legal_document (tipo PRIVACIDAD) e incrementa su versión.'
  FROM cat_legal_type WHERE codigo = 'PRIVACIDAD';

-- Vista: qué documentos vigentes le tocan a cada usuario y si ya los aceptó
CREATE OR REPLACE VIEW v_legal_pendiente AS
SELECT u.id AS user_id, d.id AS legal_document_id, t.codigo AS tipo,
       d.version, d.titulo,
       (a.id IS NOT NULL) AS aceptado
FROM users u
JOIN cat_user_type ut ON ut.id = u.user_type_id
JOIN legal_document d ON d.vigente = TRUE
JOIN cat_legal_type t ON t.id = d.legal_type_id
LEFT JOIN legal_acceptance a ON a.user_id = u.id AND a.legal_document_id = d.id
WHERE t.codigo = 'PRIVACIDAD'
   OR (t.codigo = 'TYC_EDITOR'  AND ut.codigo = 'EDITOR')
   OR (t.codigo = 'TYC_CLIENTE' AND ut.codigo = 'CLIENTE');
