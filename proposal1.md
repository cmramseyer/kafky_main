# Escenarios De Fallo Y Mejora Del Flujo Kafka

## Flujo Actual

```text
kafky_prices --catalog.events--> kafky + kafky_storage
kafky --orders.events--> kafky_storage
kafky_storage --inventory.stock.events--> kafky
kafky_storage --inventory.events--> kafky_providers
kafky_providers --inventory.receipts.events--> kafky_storage
```

Las cuatro aplicaciones usan outbox, lo cual evita perder el evento cuando falla
la transaccion de negocio. Aun asi, el sistema es de consistencia eventual y
entrega al menos una vez: debe admitir retrasos, duplicados y mensajes fuera de
orden entre particiones.

## Escenarios A Documentar

| Escenario | Situacion actual / efecto | Cambio que lo empeora | Solucion |
| --- | --- | --- | --- |
| Publicacion duplicada desde outbox | Si Kafka recibe el mensaje pero el proceso cae antes de guardar `published_at`, se republicara. Es correcto desde el punto de vista de no perder datos, pero genera duplicados. | Marcar `published_at` antes de publicar: puede perder eventos. | Mantener publicar y luego marcar; hacer idempotentes todos los consumers por `event_id` con inbox. |
| `order.created` redeliverado | `OrdersEventsConsumer` descuenta nuevamente el stock y crea otra outbox de stock. | Confiar solo en el offset Kafka o eliminar la transaccion. | Inbox unica por `event_id`, en la misma transaccion que descuento y outbox. Ya esta pendiente en `TODO.md`. |
| `inventory.stock_added` redeliverado | `InventoryReceiptsEventsConsumer` suma nuevamente el stock. | Usar `provider_order_id` sin restriccion unica ni inbox. | Misma inbox transaccional por `event_id`. |
| Orden con stock insuficiente | Se ignora silenciosamente: no descuenta ni emite un resultado. `kafky` muestra la orden como creada aunque Inventario no la acepto. | Descontar hasta cero o aceptar cantidades parciales sin contrato explicito. | Definir rechazo, reserva o cumplimiento parcial. Para aprender el flujo, publicar `inventory.stock_insufficient` con SKU, solicitado, disponible y `event_id` origen. |
| SKU inexistente en una orden | Hoy `OrdersEventsConsumer` hace `return` y el mensaje queda perdido. | Considerarlo procesado silenciosamente. | Lanzar error reintentable; tras un limite, DLQ y reconciliacion cuando llegue o se repare `product.created`. |
| SKU inexistente en un recibo | Hoy falla con `find_by!`, por lo que reintenta indefinidamente. | Reintento ilimitado: bloquea la particion. | Reintentos acotados y DLQ; crear/corregir `InventoryItem` y reprocesar. |
| Evento de precio antes de creacion local | `CatalogEventsConsumer` de `kafky` usa `find_by!` para `product.price_updated`; si falta el producto, falla. | Consumir el precio y crear un producto incompleto. | Preservar la clave Kafka por SKU y publicar creacion antes de cambios; ademas, DLQ/reintento para recuperacion y un proceso de backfill. |
| Stock antes de catalogo local | `InventoryStockEventsConsumer` falla si el producto aun no existe en `kafky`. | Ignorar el cambio de stock. | Reintentar/DLQ y reprocesar tras sincronizar catalogo. |
| Ordenes del mismo SKU en distintas particiones | El productor de `kafky` usa `order.id` como key, no SKU. Dos ordenes del mismo producto pueden llegar desordenadas a Inventario. El bloqueo de fila evita corrupcion, pero no garantiza orden de negocio. | Eliminar `InventoryItem.lock`: aparecen lost updates y stock incorrecto. | Si el orden por producto es requisito, publicar `order.created` con key `sku`; si no lo es, conservar lock e idempotencia y documentar que el orden entre ordenes no esta garantizado. |
| Actualizacion manual concurrente de stock | El controller de Inventario guarda una instancia sin `lock`; puede competir con un consumer que si bloquea la fila y sobrescribir una cantidad mas reciente. | Hacer lecturas/modificaciones sin transaccion o sin control de concurrencia. | Usar `with_lock` o actualizacion atomica tambien en la modificacion manual; generar la outbox dentro de esa misma transaccion. |
| Descripcion/categoria modificada | `kafky_prices` solo emite evento al crear o cambiar precio. Las proyecciones pueden quedar obsoletas. | Asumir que las copias se actualizan solas. | Emitir `product.updated` versionado con los campos modificados, o eventos especificos de categoria/descripcion. |
| Producto eliminado | No existe evento de borrado; `kafky` e Inventario mantienen productos fantasma. | Borrar fisicamente sin comunicarlo. | Definir `product.discontinued` o `product.deleted`; preferir baja logica para conservar trazabilidad de ordenes. |
| Evento desconocido en catalogo | Ambos consumers ignoran algunos tipos: Inventario ignora todo salvo `product.created`; `kafky` ignora tipos fuera de su `case`. Puede perderse una evolucion del contrato sin senal. | Agregar eventos al topic compartido sin validar/monitorizar consumers. | Validar esquema, registrar metricas de eventos ignorados y decidir explicitamente que consumer acepta cada tipo. |
| Contrato invalido o incompatible | Se validan tipo, fuente y version en varios consumers, pero no hay validacion completa de `event_id`, estructura ni tipos de `data`. | Cambiar campos de v1 sin versionar. | Validacion de contrato por version, tests con payloads reales y evolucion aditiva o `event_version` nueva. |
| Sin proveedores | `InventoryEventsConsumer` lanza error si no existe proveedor; actualmente puede reintentar sin final. | Crear una orden sin proveedor o descartar la alerta. | DLQ, alerta operativa y reproceso cuando se de de alta un proveedor. |
| `reorder_point = 0` | Proveedores ignora el evento. Ademas, la formula de compra no puede producir una cantidad positiva con umbral cero. | Inventar una cantidad implicita o crear ordenes de cantidad cero. | Definir que cero significa "sin reposicion automatica", o anadir un `target_quantity` explicito al contrato. |
| Bajo stock repetido | La regla actual solo emite alerta al cruzar el umbral desde arriba hacia abajo, lo que evita muchas ordenes repetidas. | Publicar `inventory.low_stock` en cada descuento bajo el umbral. | Mantener deteccion de cruce y la unicidad en proveedores por `source_event_id`; si se requieren reposiciones sucesivas, definir una politica por SKU y estado de orden abierta. |
| Proveedor recibe dos veces una orden | Esta bien cubierto: `with_lock`, bandera `delivered` y outbox en la transaccion evitan emitir dos recibos. | Quitar el lock o publicar fuera de la transaccion. | Conservar el lock, la marca de entrega y la outbox transaccional. |
| Consumer detenido o lento | Los eventos se acumulan y las proyecciones quedan atrasadas; ventas puede mostrar stock/precio antiguo. | Tratar la proyeccion local como fuente de verdad. | Medir consumer lag, edad de outbox pendiente, errores/DLQ y mostrar que stock/precio son eventualmente consistentes. |
| Reproceso historico | Un consumer nuevo puede no reconstruir correctamente si Kafka ya elimino eventos por retencion, o si los eventos no son suficientes para reconstruir estado. | Depender exclusivamente de retencion Kafka como respaldo de datos. | Definir retencion, snapshots/backfill desde las fuentes de verdad y procedimiento de reconstruccion de proyecciones. |

## Dos Diseños Importantes Para Comparar

### Orden Como Evento De Hecho, Diseño Actual

- `kafky` confirma una orden y publica `order.created`.
- Inventario decide despues si puede descontar.
- Es simple y desacoplado.
- Puede confirmar al cliente una orden que despues no se puede cumplir.

### Reserva De Stock O Saga

- `kafky` publica una solicitud de reserva.
- `kafky_storage` responde `stock.reserved` o `stock.rejected`.
- `kafky` cambia el estado visible de la orden: pendiente, confirmada o rechazada.
- Mejora la semantica de venta, pero anade estados, expiracion de reservas y
  eventos de compensacion.

## Prioridad Recomendada

1. Inbox en Inventario para los dos consumers que mutan stock.
2. DLQ y limites de reintento.
3. Decidir el resultado de stock insuficiente y SKU inexistente.
4. Corregir concurrencia de actualizacion manual de inventario.
5. Definir evolucion de catalogo: actualizacion, eliminacion y reconstruccion.
6. Anadir metricas de outbox pendiente, consumer lag, errores y DLQ.
7. Evaluar reserva de stock cuando el flujo basico sea confiable.

## Garantias De Orden

Karafka mantiene orden estricto dentro de una particion y consumer group, no
entre particiones. Por eso la key elegida para producir eventos es una decision
de negocio importante.
