# Action Cable and Solid Cable TODO

## Architecture

Each application owns an independent Action Cable endpoint and Solid Cable
database:

- `kafky` serves its own browser clients from its `/cable` endpoint.
- `kafky_storage` serves its own browser clients from its `/cable` endpoint.
- `kafky_prices` serves its own browser clients from its `/cable` endpoint.
- `kafky_providers` serves its own browser clients from its `/cable` endpoint.

Do not share a Cable database, Cable endpoint, stream names, or Rails secrets
between applications. Kafka remains the only inter-service transport. A Kafka
consumer commits a change to its local projection, then that same application
broadcasts an update to its own connected browsers.

Use Turbo Streams as the default browser integration. All applications already
load `turbo-rails`, so custom JavaScript Action Cable consumers are unnecessary
unless a future interaction cannot be represented as a Turbo Stream.

## Shared Setup For Every Application

1. Add `solid_cable` to the Gemfile and run Bundler. `kafky` already has this
   dependency.
2. Enable `action_cable/engine` in `config/application.rb`. `kafky` already
   enables it.
3. Add `config/cable.yml` with `solid_cable` for `development` and `production`.
   Keep the `test` adapter for tests.
4. Configure a separate `cable` database for both `development` and
   `production` in `config/database.yml`. Each application must use its own
   database files, for example `storage/development_cable.sqlite3` and
   `storage/production_cable.sqlite3`.
5. Generate or add the Solid Cable schema (`db/cable_schema.rb`) and initialize
   the new Cable database without rebuilding existing local application data.
6. Configure message retention and automatic trimming so old Cable messages do
   not grow the database indefinitely.
7. When an application is deployed to more than one host, replace local SQLite
   with a database shared by that application's processes. Do not share that
   database with another microservice.

Development must use Solid Cable for applications whose Rails server and
Karafka consumer run as separate processes. The `async` adapter only delivers
within one Ruby process.

## Kafky

`kafky` already has Action Cable, `solid_cable`, `db/cable_schema.rb`, and a
production Cable database configuration. Complete the following work:

1. Change the `development` adapter in `config/cable.yml` from `async` to
   `solid_cable` and add a `development.cable` database configuration.
2. Initialize the development Cable schema.
3. Add Turbo Stream subscriptions to the new-order product table.
4. In `CatalogEventsConsumer`, broadcast local product creation and price
   changes after the local product transaction commits.
5. In `InventoryStockEventsConsumer`, broadcast the updated stock after the
   local product transaction commits.
6. Render targeted partials with stable DOM IDs for product price and stock.
   Do not replace quantity inputs while a user is filling out an order form.
7. Decide how a newly created product is added to an already-open order form.
   Prefer a replaceable list container or an idempotent row update over an
   unguarded append.

## Kafky Storage

`kafky_storage` currently has Turbo but no Action Cable or Solid Cable setup.

1. Apply the shared setup.
2. Add Turbo Stream subscriptions and stable DOM targets to the inventory index
   and inventory detail views.
3. In `CatalogEventsConsumer`, publish a local UI update when an
   `InventoryItem` is created from `product.created`.
4. In `OrdersEventsConsumer` and `InventoryReceiptsEventsConsumer`, broadcast
   the available quantity only after the inventory transaction commits.
5. In `InventoryItemsController`, broadcast manual stock or reorder-point
   changes after its transaction commits so other open inventory pages update.
6. Keep the existing outbox events for Kafka. A Cable broadcast is local UI
   delivery, not a replacement for `inventory.stock_updated` or
   `inventory.low_stock`.

## Kafky Prices

`kafky_prices` currently has Turbo but no Action Cable or Solid Cable setup and
has no Kafka consumers.

1. Apply the shared setup.
2. Add Turbo Stream subscriptions and stable DOM targets to pricing product
   list and detail views.
3. Broadcast product creation, price changes, and deletion from
   `PricingProductsController` after their database transactions commit.
4. Preserve the existing catalog outbox flow. Kafka will carry catalog changes
   to other services; Cable updates only browsers connected to `kafky_prices`.

## Kafky Providers

`kafky_providers` currently has Turbo but no Action Cable or Solid Cable setup.

1. Apply the shared setup.
2. Add Turbo Stream subscriptions and stable DOM targets to provider-order list
   and detail views.
3. In `InventoryEventsConsumer`, broadcast a new provider order only when the
   low-stock event created it. Do not emit a duplicate UI update when a Kafka
   retry finds the existing order.
4. In `ProviderOrdersController#receive`, broadcast the delivered state after
   the lock and transaction have completed.
5. Keep `inventory.stock_added` in the outbox. It remains the event that
   informs `kafky_storage`; it must not be replaced with a cross-service Cable
   broadcast.

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

Run each Rails server and each active Karafka server as separate processes, then
verify the following flows with the corresponding pages open in a browser:

1. Create or change a price in `kafky_prices`; the open new-order page in
   `kafky` updates after `kafky` consumes `catalog.events`.
2. Create an order in `kafky`; `kafky_storage` updates its inventory after
   consuming `orders.events`, then `kafky` receives and displays the new stock
   from `inventory.stock.events`.
3. Trigger low stock; `kafky_providers` creates and displays the provider order
   after consuming `inventory.events`.
4. Mark that provider order as received; `kafky_storage` updates its inventory
   after consuming `inventory.receipts.events`, then `kafky` displays the
   replenished stock.
5. Confirm that every application uses its own Cable database and that no Redis
   service is required.
