## Menú para todos

Abrir **F1 → Test Round Toolkit**. La tarjeta es pública y usa los componentes nativos de TTT2.

- Sin sesión: muestra que no hay una ronda de pruebas iniciada. Los administradores pueden iniciar una.
- **Start Test Round** está siempre visible: explicación, inicio/detención y limpieza.
- **Change Role**, **Spawn Weapons** y **Bots** aparecen siempre como secciones laterales independientes. Sin una ronda de pruebas activa muestran un aviso; al iniciarla se habilitan sus herramientas.
- Al iniciar en preparación, salta el tiempo restante y ejecuta el inicio nativo de TTT2.
- Durante pruebas: cualquiera puede cambiar su propio rol/vida y darse armas.
- **Iniciar, detener, limpiar, agregar y quitar bots son exclusivos de administradores**.

Toda acción se valida en el servidor; ocultar controles no es la protección de permisos. La administración utiliza `admin.IsAdmin` / `TTT2AdminCheck`.

## Armas

Los selectores usan **la misma lista que Edit Equipment**, mediante `ShopEditor.GetEquipmentForRoleAll()`, excluyendo los items que no son armas.

Las categorías pueden superponerse: se usa el Spawn Type de Edit Equipment y también el Kind de inventario convertido mediante la API nativa de TTT2. Una escopeta puede aparecer tanto en Shotguns como en Heavy weapons.

- **Neither buyable nor spawnable** es exclusivo: sus armas no aparecen en ninguna otra lista.
- Las no spawneables pero comprables aparecen en **Not spawnable (buyable)** y en sus categorías.
- Las demás aparecen en las categorías de Spawn Type y Kind que correspondan.
- No se repite una misma arma dentro de una lista.
La clasificación utiliza los valores efectivos de Edit Equipment. Hay un grupo de otros tipos para no perder armas con un valor desconocido. Se elige y entrega un arma a la vez, únicamente a uno mismo, con confirmación de entrega. Las definiciones de armas se resuelven con herencia para reconocer correctamente el tipo de inventario. Se respetan los espacios normales del inventario: si el espacio está ocupado, se suelta automáticamente el arma bloqueante antes de dar la nueva. El arma anterior queda en el mapa. Si no se puede soltar o no hay espacio frente al jugador, se informa el motivo y no se fuerza la entrega. El servidor rechaza clases no registradas, bases y entidades arbitrarias.

La misma página **Spawn Weapons** incluye un selector de munición. Usa el registro nativo de munición spawneable de TTT2, permite elegir el tipo y entrega el contenido de una caja sin superar el máximo definido por esa entidad.

## Sesión

Permite probar solo, reduciendo temporalmente `ttt_minimum_players` a 1 y restaurándolo al terminar. Una solicitud durante preparación elimina la transición pendiente prep2begin y llama a gameloop.Begin. Si estaba esperando jugadores, activa el ciclo nativo de preparación y lo salta al terminar los hooks de preparación. Los efectos de prueba empiezan en ROUND_ACTIVE.

Los participantes comienzan como traidores. Respawn cada tres segundos, 99 créditos adicionales para compradores con menos de 10, ronda prolongada y mensajes de daño. Respeta espectadores voluntarios y roles personalizados.

Limpiar usa el reinicio nativo de TTT2 y conserva la sesión/roles. Detener restaura karma, factor de daño, estado de ronda limpia y totales de puntuación/muertes; quita todos los bots y descarta eventos de prueba mediante reinicio. La protección de karma se mantiene durante la limpieza asíncrona.

El aviso corto aparece siempre arriba a la derecha, con contorno y después del dibujo del HUD.

## Atajos

`!testround` / consola `ttt_starttestround`; `!traitor`, `!innocent`, `!detective` o `!<nombre interno del rol>`; `!health X`; `!bot X`; `!unbot`; `!clean` / `!cleanup`.

## Validación

[Análisis de migración](docs/MIGRATION.md) y [pruebas](docs/TESTING.md). Las comprobaciones automatizadas usan mocks; todavía se necesita probar el F1, la red y los loadouts de terceros dentro de Garry's Mod.
