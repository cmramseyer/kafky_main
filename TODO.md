# TODO

`integration.md` documenta la topologia y los contratos actualmente activos.
Este archivo es la unica fuente de pendientes de implementacion.

## Limpieza De `kafky`

- Remover los artefactos heredados de inventario y proveedores: la columna
  `products.reorder_threshold`, la tabla y el modelo `ProviderOrder`, su ruta,
  controlador y vista, y los adaptadores y handler de `inventory.low_stock`.
- Conservar `products.stock` unicamente como proyeccion actualizada desde
  `inventory.stock.events`.

## Inventario

- Definir el comportamiento ante una orden con stock insuficiente y, si se
  decide, publicar un evento de stock insuficiente. Actualmente no se descuenta
  stock ni se publican eventos.
- Definir el tratamiento de `order.created` con SKU inexistente: reintento,
  reconciliacion o envio a una DLQ. Actualmente se ignora.
- Definir el tratamiento final de `inventory.stock_added` con SKU inexistente.
  Actualmente el consumer falla para que Karafka lo reintente.

## Confiabilidad De Eventos

- Hacer que `order.created` publique intencionalmente un evento duplicado para
  validar que las demas integraciones toleren duplicados.
- Agregar una inbox por `event_id` en `kafky_storage` para evitar descuentos
  duplicados ante redeliveries de `order.created`.
- Agregar una inbox por `event_id` en `kafky_storage` para impedir que un
  redelivery de `inventory.stock_added` sume stock mas de una vez.
- Definir limites de reintento, una DLQ y el manejo final de errores para los
  consumers de Kafka.

## Proveedores

- Definir la reposicion para productos con `reorder_point = 0`. Actualmente
  `kafky_providers` no crea una orden de compra para esos eventos.
