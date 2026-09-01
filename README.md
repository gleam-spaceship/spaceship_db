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

## API Reference

### Connection

```gleam
// Create connection (auto-closes when callback returns)
use db <- spaceship_db.with_db(sqlite.driver("path/to/db.sqlite"))

// The connection is automatically closed at the end
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

## Error Handling

All operations return `Result` types. Errors propagate via `use` syntax:

```gleam
use db <- spaceship_db.new(sqlite.driver("db.sqlite"))
// If connection fails, execution stops with Error(String)

use prepared <- spaceship_db.prepare(db, "INVALID SQL")
// If prepare fails, execution stops with Error(String)
```

## Supported Drivers

| Driver | Package | Config |
|---|---|---|
| SQLite | Built-in | `sqlite.driver(path)` |
| D1 | Built-in | `d1.driver(binding)` |
| PostgreSQL | Coming soon | `pg(uri:)` |
| MySQL | Coming soon | `mysql(uri:)` |
| Turso | Coming soon | `turso(uri:, api_token:)` |

### SQLite (Local Development)

```gleam
import spaceship_db/drivers/sqlite

use db <- spaceship_db.with_db(sqlite.driver("./app.db"))
```

### D1 (Cloudflare Workers)

```gleam
import spaceship_db/drivers/d1

// In your Cloudflare entry point:
pub fn main(req, env, ctx) {
  // Initialize D1 driver with binding name "DB"
  use db <- spaceship_db.with_db(d1.driver("DB"))
  
  // Use database
  use prepared <- spaceship_db.prepare(db, "SELECT * FROM notes")
  use rows <- spaceship_db.exec(prepared, [])
  
  // Handle request
}
```

The D1 driver works with Cloudflare's D1 database. The binding name should match what you defined in your `wrangler.toml`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "my-database"
database_id = "xxx-xxx-xxx"
```

## Requirements

- Gleam v1.0.0+
- JavaScript runtime with `node:sqlite` support (Node.js 22+)

## License

Apache-2.0
