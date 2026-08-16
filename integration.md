# Integracion de `kafky`

## Funcion

`kafky` es la aplicacion de ventas. Mantiene una proyeccion local de productos,
precios y stock para mostrar el catalogo y crear ordenes de clientes.

No es fuente de verdad para catalogo, precios ni inventario:

- `kafky_prices` administra productos y precios.
- `kafky_storage` administra el stock.

Al confirmar una orden, `kafky` guarda el evento en su outbox y lo publica de
forma asincrona en Kafka.

## Eventos Publicados

| Evento | Topic | Cuando se publica |
| --- | --- | --- |
| `order.created` v1 | `orders.events` | Cuando se crea una orden de cliente. |

Los eventos pendientes se publican mediante:

```bash
bin/rails outbox:publish
```

## Consumers

| Consumer | Topic | Eventos aceptados | Efecto |
| --- | --- | --- | --- |
| `CatalogEventsConsumer` | `catalog.events` | `product.created` v1, `product.price_updated` v1 desde `kafky_prices` | Crea o actualiza productos locales por `sku`; actualiza precios y crea categorias locales cuando corresponde. |
| `InventoryStockEventsConsumer` | `inventory.stock.events` | `inventory.stock_updated` v1 desde `kafky_storage` | Actualiza el campo `stock` del producto local por `sku`. |

`kafky` no consume `orders.events`, `inventory.events` ni
`inventory.receipts.events`; esas responsabilidades pertenecen a
`kafky_storage` y `kafky_providers`.

# Integracion de `kafky_storage`

## Funcion

`kafky_storage` es la fuente de verdad para el inventario. Mantiene el stock
disponible y el `reorder_point` de cada producto.

La aplicacion crea su inventario local a partir del catalogo, descuenta stock
cuando recibe ordenes de clientes y suma unidades cuando los proveedores
entregan una reposicion. Tambien detecta cuando una orden deja un producto bajo
su umbral de reposicion.

Los cambios de inventario y las alertas de bajo stock se guardan primero en la
outbox y luego se publican de forma asincrona en Kafka.

## Eventos Publicados

| Evento | Topic | Cuando se publica |
| --- | --- | --- |
| `inventory.stock_updated` v1 | `inventory.stock.events` | Cuando cambia `available_quantity` por una orden valida, una reposicion recibida o una actualizacion manual. |
| `inventory.low_stock` v1 | `inventory.events` | Cuando una orden deja el stock en `reorder_point` o menos, despues de haber estado por encima del umbral. |

Los eventos pendientes se publican mediante:

```bash
bin/rails outbox:publish
```

## Consumers

| Consumer | Topic | Eventos aceptados | Efecto |
| --- | --- | --- | --- |
| `CatalogEventsConsumer` | `catalog.events` | `product.created` v1 desde `kafky_prices` | Crea el `InventoryItem` local por `sku`. |
| `OrdersEventsConsumer` | `orders.events` | `order.created` v1 desde `kafky` | Descuenta stock si el producto existe y hay cantidad suficiente; publica la actualizacion de stock y, si corresponde, la alerta de bajo stock. |
| `InventoryReceiptsEventsConsumer` | `inventory.receipts.events` | `inventory.stock_added` v1 desde `kafky_providers` | Suma el stock entregado por el proveedor y publica la actualizacion de stock. |

## Comportamiento Ante Casos No Procesables

- Una orden con un SKU inexistente se ignora por ahora.
- Una orden cuya cantidad supera el stock disponible no descuenta stock ni
  publica eventos.
- Un recibo con un SKU inexistente falla para que Karafka pueda reintentarlo.

# Integracion de `kafky_prices`

## Funcion

`kafky_prices` es la fuente de verdad para productos y precios. Administra el
`sku`, la descripcion, el precio y la categoria de cada producto.

Cuando crea un producto o cambia su precio, guarda el cambio y el evento
pendiente en su outbox dentro de la misma transaccion. Las aplicaciones que
consumen estos eventos mantienen sus propias proyecciones locales del catalogo.

## Eventos Publicados

| Evento | Topic | Cuando se publica |
| --- | --- | --- |
| `product.created` v1 | `catalog.events` | Cuando se crea un producto. |
| `product.price_updated` v1 | `catalog.events` | Cuando cambia el precio de un producto. |

Una actualizacion exclusiva de descripcion o categoria no publica un evento
actualmente. La eliminacion de un producto tampoco publica un evento.

Los eventos pendientes se publican mediante:

```bash
bin/rails outbox:publish
```

## Consumers

`kafky_prices` no tiene consumers ni topics de consumo configurados.

# Integracion de `kafky_providers`

## Funcion

`kafky_providers` es la fuente de verdad para los proveedores y las ordenes de
reposicion. Recibe alertas de bajo stock, asigna un proveedor aleatorio y crea
la orden de compra correspondiente.

La cantidad solicitada repone el stock hasta dos veces el umbral de reposicion:
`2 * reorder_point - available_quantity`.

Cuando una orden de proveedor se marca como recibida, la aplicacion registra la
entrega y crea un evento para que Inventario incremente el stock.

## Eventos Publicados

| Evento | Topic | Cuando se publica |
| --- | --- | --- |
| `inventory.stock_added` v1 | `inventory.receipts.events` | Cuando una orden de proveedor se marca como recibida. |

El evento se guarda en la outbox dentro de la misma transaccion que marca la
orden como entregada.

Los eventos pendientes se publican mediante:

```bash
bin/rails outbox:publish
```

## Consumers

| Consumer | Topic | Eventos aceptados | Efecto |
| --- | --- | --- | --- |
| `InventoryEventsConsumer` | `inventory.events` | `inventory.low_stock` v1 desde `kafky_storage` | Asigna un proveedor aleatorio y crea una unica orden de reposicion por evento. |

## Comportamiento Ante Casos No Procesables

- Si no hay proveedores, el consumer produce un error para que Karafka pueda
  reintentar el mensaje.
- Si `reorder_point` es `0`, no crea una orden de reposicion por ahora.
- Recibir nuevamente una orden ya entregada no genera otro evento de stock.
