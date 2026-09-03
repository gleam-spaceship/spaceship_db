import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import spaceship_db.{type AsyncDb, type Db}
import spaceship_db/value.{type Value}

pub type Migration {
  Migration(name: String, up: List(String), down: List(String))
}

const tracker_table = "__spaceship_migrations"

fn create_tracker_query() -> String {
  "CREATE TABLE IF NOT EXISTS "
  <> tracker_table
  <> " (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, applied_at TEXT NOT NULL)"
}

fn record_query() -> String {
  "INSERT INTO "
  <> tracker_table
  <> " (name, applied_at) VALUES (?, datetime('now'))"
}

fn remove_query() -> String {
  "DELETE FROM " <> tracker_table <> " WHERE name = ?"
}

fn is_applied_query() -> String {
  "SELECT 1 FROM " <> tracker_table <> " WHERE name = ?"
}

fn text(v: String) -> Value {
  value.text(v)
}

/// Apply all pending migrations
pub fn migrate(db: Db, migrations: List(Migration)) -> Result(Nil, String) {
  use prepared <- spaceship_db.prepare(db, create_tracker_query())
  use _ <- spaceship_db.exec(prepared, [])
  run_up(db, migrations)
}

/// Rollback last N migrations
pub fn rollback(
  db: Db,
  migrations: List(Migration),
  steps: Int,
) -> Result(Nil, String) {
  let to_rollback =
    list.take(list.reverse(migrations), steps) |> list.map(fn(m) { m.name })
  run_down(db, migrations, to_rollback)
}

/// Apply all pending migrations (async)
pub fn migrate_async(
  db: AsyncDb,
  migrations: List(Migration),
) -> Promise(Result(Nil, String)) {
  use prepared <- spaceship_db.prepare_async(db, create_tracker_query())
  use _ <- spaceship_db.exec_async(prepared, [])
  run_up_async(db, migrations)
}

/// Rollback last N migrations (async)
pub fn rollback_async(
  db: AsyncDb,
  migrations: List(Migration),
  steps: Int,
) -> Promise(Result(Nil, String)) {
  let to_rollback =
    list.take(list.reverse(migrations), steps) |> list.map(fn(m) { m.name })
  run_down_async(db, migrations, to_rollback)
}

// ── Internal (Sync) ──────────────────────────────────────────────

fn is_applied(db: Db, name: String) -> Result(Bool, String) {
  use prepared <- spaceship_db.prepare(db, is_applied_query())
  use rows <- spaceship_db.exec(prepared, [text(name)])
  case rows {
    [_, ..] -> Ok(True)
    [] -> Ok(False)
  }
}

fn run_up(db: Db, migrations: List(Migration)) -> Result(Nil, String) {
  case migrations {
    [] -> Ok(Nil)
    [migration, ..rest] -> {
      use applied <- result.try(is_applied(db, migration.name))
      case applied {
        True -> run_up(db, rest)
        False -> {
          case run_queries(db, migration.up) {
            Ok(_) -> {
              use prepared <- spaceship_db.prepare(db, record_query())
              use _ <- spaceship_db.exec(prepared, [text(migration.name)])
              io.println("Applied: " <> migration.name)
              run_up(db, rest)
            }
            Error(e) ->
              Error("Migration " <> migration.name <> " failed: " <> e)
          }
        }
      }
    }
  }
}

fn run_down(
  db: Db,
  migrations: List(Migration),
  names: List(String),
) -> Result(Nil, String) {
  case names {
    [] -> Ok(Nil)
    [name, ..rest] -> {
      let migration = list.find(migrations, fn(m) { m.name == name })
      case migration {
        Ok(m) -> {
          case run_queries(db, m.down) {
            Ok(_) -> {
              use prepared <- spaceship_db.prepare(db, remove_query())
              use _ <- spaceship_db.exec(prepared, [text(m.name)])
              io.println("Rolled back: " <> m.name)
              run_down(db, migrations, rest)
            }
            Error(e) -> Error("Rollback " <> m.name <> " failed: " <> e)
          }
        }
        Error(_) -> Error("Migration not found: " <> name)
      }
    }
  }
}

fn run_queries(db: Db, queries: List(String)) -> Result(Nil, String) {
  case queries {
    [] -> Ok(Nil)
    [query, ..rest] -> {
      use prepared <- spaceship_db.prepare(db, query)
      use _ <- spaceship_db.exec(prepared, [])
      run_queries(db, rest)
    }
  }
}

// ── Internal (Async) ─────────────────────────────────────────────

fn run_up_async(
  db: AsyncDb,
  migrations: List(Migration),
) -> Promise(Result(Nil, String)) {
  case migrations {
    [] -> promise.resolve(Ok(Nil))
    [migration, ..rest] -> {
      use prepared <- spaceship_db.prepare_async(db, is_applied_query())
      use rows <- spaceship_db.exec_async(prepared, [text(migration.name)])
      case rows {
        [_, ..] -> run_up_async(db, rest)
        [] -> {
          run_queries_async(db, migration.up)
          |> promise.await(fn(result) {
            case result {
              Ok(_) -> {
                use prepared <- spaceship_db.prepare_async(db, record_query())
                use _ <- spaceship_db.exec_async(prepared, [
                  text(migration.name),
                ])
                io.println("Applied: " <> migration.name)
                run_up_async(db, rest)
              }
              Error(e) ->
                promise.resolve(Error(
                  "Migration " <> migration.name <> " failed: " <> e,
                ))
            }
          })
        }
      }
    }
  }
}

fn run_down_async(
  db: AsyncDb,
  migrations: List(Migration),
  names: List(String),
) -> Promise(Result(Nil, String)) {
  case names {
    [] -> promise.resolve(Ok(Nil))
    [name, ..rest] -> {
      let migration = list.find(migrations, fn(m) { m.name == name })
      case migration {
        Ok(m) -> {
          run_queries_async(db, m.down)
          |> promise.await(fn(result) {
            case result {
              Ok(_) -> {
                use prepared <- spaceship_db.prepare_async(db, remove_query())
                use _ <- spaceship_db.exec_async(prepared, [text(m.name)])
                io.println("Rolled back: " <> m.name)
                run_down_async(db, migrations, rest)
              }
              Error(e) ->
                promise.resolve(Error("Rollback " <> m.name <> " failed: " <> e))
            }
          })
        }
        Error(_) -> promise.resolve(Error("Migration not found: " <> name))
      }
    }
  }
}

fn run_queries_async(
  db: AsyncDb,
  queries: List(String),
) -> Promise(Result(Nil, String)) {
  case queries {
    [] -> promise.resolve(Ok(Nil))
    [query, ..rest] -> {
      use prepared <- spaceship_db.prepare_async(db, query)
      use _ <- spaceship_db.exec_async(prepared, [])
      run_queries_async(db, rest)
    }
  }
}
