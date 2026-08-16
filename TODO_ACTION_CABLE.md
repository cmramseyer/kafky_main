# Remaining Action Cable and Solid Cable TODO

## Architecture

Each application owns an independent Action Cable endpoint, Cable database,
stream namespace, and Rails secret. Do not share any of these across
applications.

Kafka remains the only inter-service transport. A consumer commits a change to
its local projection, then that same application broadcasts an update to its
own connected browsers.

Use Turbo Streams as the default browser integration. Custom JavaScript Action
Cable consumers are unnecessary unless a future interaction cannot be expressed
as a Turbo Stream.

Development must use Solid Cable whenever Rails and Karafka run as separate
processes. The `async` adapter only delivers messages within one Ruby process.

## Kafky

1. Add newly created products to an already-open new-order form after
   `CatalogEventsConsumer` processes `product.created`.
2. Preserve quantity inputs already filled by the user while adding the new row.
3. Make the insertion idempotent so Kafka retries cannot duplicate a product row.

## Kafky Storage

1. Broadcast manual changes from `InventoryItemsController#update` after its
   transaction commits.
2. Update the availability and reorder-point targets in other open inventory
   index and detail pages.
3. Preserve the existing Kafka outbox events. A Cable broadcast is local UI
   delivery, not a replacement for `inventory.stock_updated` or
   `inventory.low_stock`.

## Kafky Prices

1. Add `solid_cable`, enable `action_cable/engine`, and configure Solid Cable
   for development with a dedicated Cable database and schema.
2. Add Turbo Stream subscriptions and stable DOM targets to pricing product list
   and detail views.
3. Broadcast product creation, price changes, and deletion from
   `PricingProductsController` after the corresponding transaction commits.
4. Preserve the catalog outbox flow. Kafka informs other services; Cable updates
   only browsers connected to `kafky_prices`.

## Kafky Providers

1. Broadcast the delivered state from `ProviderOrdersController#receive` after
   the lock and transaction have completed.
2. Add stable Turbo Stream targets to provider-order index and detail pages so
   the delivered label and receive action stay synchronized across open pages.
3. Keep `inventory.stock_added` in the outbox. It informs `kafky_storage` and
   must not be replaced with a cross-service Cable broadcast.

## Broadcast Rules

- Broadcast only after the database change is committed.
- Keep the database projection as the source of truth. A page reload must show
  the correct state if a browser disconnects or misses a broadcast.
- Use signed `turbo_stream_from` streams and application-specific stream names.
- Prefer `replace` or `update` broadcasts with stable DOM IDs so consumer
  retries are safe for the UI.
- Do not place sensitive data on a shared or global stream. Add authorization
  before introducing user-specific streams.
- Do not use Action Cable as an inter-service event bus. Publish cross-service
  facts through the existing Kafka outbox pattern.

## End-To-End Verification

Run each Rails server, active Karafka server, and outbox publisher separately.
Keep the affected page open in a browser while verifying these flows:

1. Create or change a price in `kafky_prices`; the open new-order page in
   `kafky` reflects catalog changes after consuming `catalog.events`.
2. Create an order in `kafky`; `kafky_storage` updates its inventory after
   consuming `orders.events`, then `kafky` displays the new stock from
   `inventory.stock.events`.
3. Trigger low stock; `kafky_providers` creates and displays the purchase order
   after consuming `inventory.events`.
4. Mark that purchase order as received; `kafky_providers` synchronizes its
   delivered state, then `kafky_storage` and `kafky` display the replenished
   stock after consuming `inventory.receipts.events`.
