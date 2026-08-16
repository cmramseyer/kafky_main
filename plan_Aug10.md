# Plan: Proximos Pasos De `TODO.md`

## Alcance Y Orden

Este plan toma `TODO.md` como fuente de pendientes e `integration.md` como
contrato activo. Se implementara en este orden:

1. Limpiar los artefactos heredados de `kafky`.
2. Definir y aplicar las politicas para mensajes no procesables.
3. Hacer idempotentes los consumers mutantes de `kafky_storage`.
4. Configurar reintentos y DLQ para los consumers.
5. Cerrar la regla de reposicion para `reorder_point = 0`.
6. Actualizar contratos, pruebas y pendientes.

Las decisiones de producto de las secciones correspondientes deben confirmarse
antes de implementar esos cambios.

## 1. Limpieza De `kafky`

### Objetivo

Eliminar la responsabilidad heredada de inventario y proveedores de la app de
ventas. `products.stock` queda como una proyeccion local actualizada solo por
`inventory.stock_updated` desde `kafky_storage`.

### Cambios

- Crear una migracion reversible que elimine `products.reorder_threshold` y la
  tabla `provider_orders` de `kafky`.
- Eliminar el modelo `ProviderOrder`, `ProviderOrdersController`, su ruta, la
  vista y el enlace a ordenes de proveedor desde la lista de ordenes.
- Eliminar `ProviderOrderRequestHandler`.
- Eliminar los adaptadores y objetos de
  `app/events/inventory_low_stock_event/`.
- Simplificar las validaciones de `Product`: conservar la validacion de `stock`
  y retirar la de `reorder_threshold`.
- Confirmar que ningun flujo de creacion de orden modifica `products.stock`.

### Verificacion

- La aplicacion `kafky` inicia y permite listar y crear ordenes sin las rutas ni
  constantes eliminadas.
- `InventoryStockEventsConsumer` sigue actualizando el stock local por `sku`.

## 2. Politica Para Mensajes No Procesables

### Orden Con Stock Insuficiente

**Decision pendiente.** Se recomienda rechazar la linea sin descontar stock y
publicar `inventory.stock_insufficient` v1. El evento debe incluir el
`event_id` de la orden origen, `sku`, cantidad solicitada y cantidad disponible.

### Implementacion Tras La Decision

- Extender la outbox y el publicador de `kafky_storage` para el nuevo evento y
  topic que se acuerde.
- En `OrdersEventsConsumer`, detectar cantidad mayor que
  `available_quantity`, persistir el resultado definido y no publicar
  `inventory.stock_updated`.
- Si se publica el evento, definir tambien su consumer o destino operativo;
  `kafky` actualmente no consume resultados de ordenes.

### `order.created` Con SKU Inexistente

**Decision pendiente.** Se recomienda tratarlo como inconsistencia transitoria:
reintentar para permitir que llegue `product.created`; al agotar los intentos,
enviar el mensaje a DLQ para reconciliacion y reproceso.

- Sustituir el `return unless inventory_item` de `OrdersEventsConsumer` por un
  error de dominio reintentable.
- No registrar el evento como procesado mientras el SKU no exista.
- Documentar el procedimiento para crear o corregir el `InventoryItem` y
  reprocesar la DLQ.

### `inventory.stock_added` Con SKU Inexistente

- Mantener el fallo actual como reintentable.
- Al agotar reintentos, mover el mensaje a la DLQ de recibos.
- Reconciliar el catalogo/inventario y reprocesar el mensaje desde la DLQ.

## 3. Inbox En `kafky_storage`

### Objetivo

Evitar que redeliveries de `order.created` e `inventory.stock_added` modifiquen
el inventario mas de una vez o generen eventos de outbox duplicados.

### Cambios

- Crear una tabla y modelo `ProcessedEvent` (o nombre equivalente) con
  `event_id` unico, `event_type`, `source` y timestamps.
- Dentro de la misma transaccion de cada consumer, crear el registro inbox,
  bloquear el `InventoryItem`, cambiar el stock y crear los eventos de outbox.
- Si el `event_id` ya existe, terminar el procesamiento sin modificar stock ni
  outbox.
- Registrar el inbox solo cuando el procesamiento haya terminado o cuando se
  haya persistido el rechazo definitivo acordado; no hacerlo antes de una falla
  reintentable.
- Aplicar el mecanismo a `OrdersEventsConsumer` e
  `InventoryReceiptsEventsConsumer`.

### Verificacion

- Dos entregas del mismo `order.created` descuentan una sola vez y producen una
  sola actualizacion de stock.
- Dos entregas del mismo `inventory.stock_added` suman una sola vez y producen
  una sola actualizacion de stock.
- Si falla la transaccion, no quedan ni inbox ni cambios de stock parciales.

## 4. Reintentos, DLQ Y Errores De Kafka

### Objetivo

Impedir que un mensaje no procesable bloquee indefinidamente una particion y
preservar el mensaje para revision y reproceso.

### Cambios

- Configurar `dead_letter_queue` en cada topic consumidor de Karafka con limite
  de reintentos explicito y conteo independiente por mensaje.
- Definir topics de DLQ separados por aplicacion y flujo, por ejemplo:
  `kafky_storage.orders.dlq`, `kafky_storage.receipts.dlq` y
  `kafky_providers.inventory.dlq`.
- Definir una jerarquia de errores de dominio para distinguir validaciones
  definitivas de fallas transitorias, como catalogo aun no sincronizado o falta
  temporal de proveedores.
- Establecer limite, backoff, registro estructurado y responsable operativo de
  cada DLQ. El valor concreto debe quedar documentado antes de configurar las
  rutas.
- Mantener los payloads y headers originales al despachar a DLQ para permitir
  trazabilidad y reproceso.

### Verificacion

- Un payload invalido se envia a DLQ despues del limite configurado y la
  particion continua.
- Un SKU que aparece antes de agotar los reintentos se procesa normalmente.
- Un mensaje de DLQ puede inspeccionarse y reprocesarse sin cambiar su
  `event_id`.

## 5. Reposicion Con `reorder_point = 0`

### Decision Pendiente

Se recomienda que `reorder_point = 0` signifique que no hay reposicion
automatica. En ese caso `kafky_storage` no debe publicar `inventory.low_stock`
para ese producto y `kafky_providers` no necesita una excepcion especial.

Si el negocio requiere reponer esos productos, el contrato debe incorporar una
cantidad objetivo explicita: con un umbral cero no se puede derivar la formula
actual `2 * reorder_point - available_quantity`.

### Cambios Tras La Decision

- Si no hay reposicion automatica, reforzar en `kafky_storage` la condicion de
  emision de `inventory.low_stock` y retirar el retorno silencioso de
  `InventoryEventsConsumer`.
- Si se define una cantidad objetivo, versionar o extender el contrato de
  `inventory.low_stock`, validar la nueva regla en proveedores y probar la
  cantidad de compra.

## 6. Pruebas, Contratos Y Cierre

- Crear pruebas de consumer para orden valida, orden duplicada, recibo valido,
  recibo duplicado, stock insuficiente y SKU inexistente.
- Añadir pruebas de outbox para asegurar que los eventos se crean en la misma
  transaccion que el cambio de inventario.
- Probar la configuracion de DLQ y el reproceso de mensajes fallidos.
- Actualizar `integration.md` con las decisiones finales, eventos nuevos,
  topics de DLQ, semantica de inbox y casos no procesables.
- Retirar de `TODO.md` cada pendiente solo despues de implementar, probar y
  documentar el comportamiento acordado.
