# spaceship_db

Reusable database API for Gleam targeting JavaScript.

## Installation

```sh
gleam add spaceship_db
```

## Quick Start

```gleam
import spaceship_db
import spaceship_db/value
import spaceship_db/drivers/sqlite

pub fn main() -> Nil {
  // Connect to database (auto-closes when done)
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  // Create table
  use prepared <- spaceship_db.prepare(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
  use _ <- spaceship_db.exec(prepared, [])

  // Insert data
  use prepared <- spaceship_db.prepare(db, "INSERT INTO users (name) VALUES (?)")
  use _ <- spaceship_db.exec(prepared, [value.text("Alice")])

  // Query data
  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users")
  use rows <- spaceship_db.exec(prepared, [])

  // Get first row
  let first = spaceship_db.get_one(rows)

  // Get all rows
  let all = spaceship_db.get_all(rows)
}
```

## Type-Safe Decoding

Use `gleam/dynamic/decode` to decode query results into typed values:

```gleam
import gleam/dynamic/decode
import spaceship_db
import spaceship_db/value
import spaceship_db/drivers/sqlite

type User {
  User(id: Int, name: String)
}

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field(0, decode.int)
  use name <- decode.field(1, decode.string)
  decode.success(User(id:, name:))
}

pub fn main() -> Nil {
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  use prepared <- spaceship_db.prepare(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
  use _ <- spaceship_db.exec(prepared, [])

  use prepared <- spaceship_db.prepare(db, "INSERT INTO users (name) VALUES (?)")
  use _ <- spaceship_db.exec(prepared, [value.text("Bob")])

  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users")
  use rows <- spaceship_db.exec(prepared, [])

  // Decode all rows
  let users = spaceship_db.decode_all(rows, user_decoder())

  // Decode single row
  let user = spaceship_db.decode_one(rows, user_decoder())
}
```

## Migrations

Manage database schema changes with versioned migrations:

```gleam
import spaceship_db
import spaceship_db/migration
import spaceship_db/drivers/sqlite

pub fn main() -> Nil {
  let migrations = [
    migration.Migration(
      name: "001_create_users",
      up: ["CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)"],
      down: ["DROP TABLE users"],
    ),
    migration.Migration(
      name: "002_add_email",
      up: ["ALTER TABLE users ADD COLUMN email TEXT"],
      down: ["ALTER TABLE users DROP COLUMN email"],
    ),
  ]

  use db <- spaceship_db.with_db(sqlite.driver("app.db"))

  // Apply all pending migrations
  let result = migration.migrate(db, migrations)

  // Rollback last 1 migration
  let result = migration.rollback(db, migrations, 1)
}
```

Migrations are idempotent — running `migrate()` multiple times only applies pending migrations. Each migration runs in a transaction for safety.

### Async Migrations

```gleam
use db <- spaceship_db.with_async_db(sqlite.async_driver("app.db"))
use result <- promise.await(migration.migrate_async(db, migrations))
```

## API Reference

### Connection

```gleam
// Sync connection (auto-closes when callback returns)
use db <- spaceship_db.with_db(sqlite.driver("path/to/db.sqlite"))

// Async connection
use db <- spaceship_db.with_async_db(sqlite.async_driver("path/to/db.sqlite"))
```

### Prepared Statements

Statements are reusable with different parameters:

```gleam
use prepared <- spaceship_db.prepare(db, "SELECT * FROM users WHERE id = ?")

// Execute with different params
use rows1 <- spaceship_db.exec(prepared, [value.int(1)])
use rows2 <- spaceship_db.exec(prepared, [value.int(2)])
```

### Parameter Binding

```gleam
value.int(42)          // Integer
value.float(3.14)      // Float
value.text("hello")    // Text
value.bool(True)       // Boolean
value.blob(<<1, 2, 3>>) // Binary
value.null()           // Null
```

### Results

```gleam
use rows <- spaceship_db.exec(prepared, [])

// Option(Dynamic) — None if empty
let first = spaceship_db.get_one(rows)

// List(Dynamic) — all rows
let all = spaceship_db.get_all(rows)
```

### Transactions

```gleam
spaceship_db.transaction(db, fn(tx) {
  use prepared <- spaceship_db.prepare(tx, "UPDATE accounts SET balance = balance - ?")
  use _ <- spaceship_db.exec(prepared, [value.float(100.0)])

  use prepared <- spaceship_db.prepare(tx, "UPDATE accounts SET balance = balance + ?")
  use _ <- spaceship_db.exec(prepared, [value.float(100.0)])

  Ok(Nil)
})
```

### Async Transactions

```gleam
spaceship_db.async_transaction(db, fn(tx) {
  use tx_result <- spaceship_db.exec_async_tx(
    tx,
    "UPDATE accounts SET balance = balance - ?",
    [value.float(100.0)],
  )
  let #(rows, tx) = tx_result

  use tx_result <- spaceship_db.exec_async_tx(
    tx,
    "UPDATE accounts SET balance = balance + ?",
    [value.float(100.0)],
  )
  let #(rows, _tx) = tx_result

  promise.resolve(Ok(Nil))
})
```

For Turso's baton-based transactions, the updated transaction state is carried through the callback chain:

```gleam
spaceship_db.async_transaction(db, fn(tx) {
  use tx_result <- spaceship_db.exec_async_tx(tx, "INSERT INTO logs (msg) VALUES (?)", [value.text("start")])
  let #(_rows, tx) = tx_result

  // tx now contains the updated Turso baton for the next request
  use tx_result <- spaceship_db.exec_async_tx(tx, "UPDATE counters SET count = count + 1", [])
  let #(_rows, _tx) = tx_result

  promise.resolve(Ok(Nil))
})
```

## Error Handling

All operations return `Result` types. Errors propagate via `use` syntax:

```gleam
use db <- spaceship_db.with_db(sqlite.driver("db.sqlite"))
// If connection fails, execution stops with Error(String)

use prepared <- spaceship_db.prepare(db, "INVALID SQL")
// If prepare fails, execution stops with Error(String)
```

## Supported Drivers

| Driver | Config | Sync | Async | Transactions |
|---|---|---|---|---|
| SQLite | `sqlite.driver(path)` | ✓ | ✓ | ✓ |
| D1 | `d1.driver(binding)` | — | ✓ | ✓ (baton) |
| Turso | `turso.driver(url, token)` | — | ✓ | ✓ (baton) |

### SQLite (Local Development)

```gleam
import spaceship_db/drivers/sqlite

// Sync
use db <- spaceship_db.with_db(sqlite.driver("./app.db"))

// Async
use db <- spaceship_db.with_async_db(sqlite.async_driver("./app.db"))
```

### D1 (Cloudflare Workers)

```gleam
import spaceship_db/drivers/d1

pub fn main(req, env, ctx) {
  use db <- spaceship_db.with_async_db(d1.driver("DB"))

  use prepared <- spaceship_db.prepare_async(db, "SELECT * FROM notes")
  use rows <- spaceship_db.exec_async(prepared, [])

  // Handle request
}
```

The binding name should match your `wrangler.toml`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "my-database"
database_id = "xxx-xxx-xxx"
```

### Turso (SQL over HTTP)

Uses Turso's `/v2/pipeline` HTTP API. No libSQL client required — works in any JavaScript runtime with Fetch support.

```gleam
import spaceship_db
import spaceship_db/drivers/turso

pub fn main() -> Nil {
  use db <- spaceship_db.with_async_db(
    turso.driver("https://your-db.turso.io", "your-token"),
  )

  use prepared <- spaceship_db.prepare_async(db, "SELECT * FROM users")
  use rows <- spaceship_db.exec_async(prepared, [])
}
```

Turso URLs using `turso://` or `libsql://` are converted to HTTPS automatically.

## Requirements

- Gleam v1.0.0+
- JavaScript runtime with Fetch support for D1 and Turso drivers
- Node.js 22+ for the SQLite driver

## License

Apache-2.0
