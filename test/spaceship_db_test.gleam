import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option
import gleam/result
import gleeunit
import spaceship_db
import spaceship_db/drivers/sqlite
import spaceship_db/value

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn connect_and_query_test() -> Result(Nil, String) {
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  // Create table
  use prepared <- spaceship_db.prepare(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec(prepared, [])

  // Insert
  use prepared <- spaceship_db.prepare(
    db,
    "INSERT INTO users (name) VALUES (?)",
  )
  use _ <- spaceship_db.exec(prepared, [value.text("Alice")])

  // Query all
  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users")
  use rows <- spaceship_db.exec(prepared, [])

  assert list.length(rows) == 1
  Ok(Nil)
}

pub fn get_one_test() -> Result(Nil, String) {
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  use prepared <- spaceship_db.prepare(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec(prepared, [])

  use prepared <- spaceship_db.prepare(
    db,
    "INSERT INTO users (name) VALUES (?)",
  )
  use _ <- spaceship_db.exec(prepared, [value.text("Bob")])

  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users WHERE id = ?")
  use rows <- spaceship_db.exec(prepared, [value.int(1)])

  assert option.is_some(spaceship_db.get_one(rows))
  Ok(Nil)
}

type User {
  User(id: Int, name: String)
}

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field(0, decode.int)
  use name <- decode.field(1, decode.string)
  decode.success(User(id:, name:))
}

pub fn decode_all_test() -> Result(Nil, String) {
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  use prepared <- spaceship_db.prepare(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec(prepared, [])

  use prepared <- spaceship_db.prepare(
    db,
    "INSERT INTO users (name) VALUES (?)",
  )
  use _ <- spaceship_db.exec(prepared, [value.text("Alice")])

  use prepared <- spaceship_db.prepare(
    db,
    "INSERT INTO users (name) VALUES (?)",
  )
  use _ <- spaceship_db.exec(prepared, [value.text("Bob")])

  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users")
  use rows <- spaceship_db.exec(prepared, [])

  let users = spaceship_db.decode_all(rows, user_decoder())
  assert result.is_ok(users)
  assert list.length(result.unwrap(users, [])) == 2
  Ok(Nil)
}

pub fn decode_one_test() -> Result(Nil, String) {
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  use prepared <- spaceship_db.prepare(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec(prepared, [])

  use prepared <- spaceship_db.prepare(
    db,
    "INSERT INTO users (name) VALUES (?)",
  )
  use _ <- spaceship_db.exec(prepared, [value.text("Charlie")])

  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users WHERE id = ?")
  use rows <- spaceship_db.exec(prepared, [value.int(1)])

  let user = spaceship_db.decode_one(rows, user_decoder())
  assert result.is_ok(user)
  assert result.unwrap(user, User(0, "")).name == "Charlie"
  Ok(Nil)
}

pub fn decode_one_not_found_test() -> Result(Nil, String) {
  use db <- spaceship_db.with_db(sqlite.driver(":memory:"))

  use prepared <- spaceship_db.prepare(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec(prepared, [])

  use prepared <- spaceship_db.prepare(db, "SELECT * FROM users WHERE id = ?")
  use rows <- spaceship_db.exec(prepared, [value.int(999)])

  case spaceship_db.decode_one(rows, user_decoder()) {
    Ok(_) -> panic as "Expected error for empty result"
    Error(msg) -> {
      assert msg == "No rows returned"
      Ok(Nil)
    }
  }
}

pub fn async_transaction_commit_test() -> Promise(Result(Nil, String)) {
  use db <- spaceship_db.with_async_db(sqlite.async_driver(":memory:"))

  use prepared <- spaceship_db.prepare_async(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec_async(prepared, [])

  spaceship_db.async_transaction(db, fn(tx) {
    use tx_result <- spaceship_db.exec_async_tx(
      tx,
      "INSERT INTO users (name) VALUES (?)",
      [value.text("Alice")],
    )
    let #(rows, tx) = tx_result
    assert rows == []

    use tx_result <- spaceship_db.exec_async_tx(
      tx,
      "INSERT INTO users (name) VALUES (?)",
      [value.text("Bob")],
    )
    let #(rows, _tx) = tx_result
    assert rows == []

    use prepared <- spaceship_db.prepare_async(db, "SELECT * FROM users")
    use _ <- spaceship_db.exec_async(prepared, [])
    promise.resolve(Ok(Nil))
  })
}

pub fn async_transaction_rollback_test() -> Promise(Result(Nil, String)) {
  use db <- spaceship_db.with_async_db(sqlite.async_driver(":memory:"))

  use prepared <- spaceship_db.prepare_async(
    db,
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)",
  )
  use _ <- spaceship_db.exec_async(prepared, [])

  // Insert a user outside the transaction
  use prepared <- spaceship_db.prepare_async(
    db,
    "INSERT INTO users (name) VALUES (?)",
  )
  use _ <- spaceship_db.exec_async(prepared, [value.text("Alice")])

  // Try to insert and rollback
  spaceship_db.async_transaction(db, fn(tx) {
    use _ <- spaceship_db.exec_async_tx(
      tx,
      "INSERT INTO users (name) VALUES (?)",
      [value.text("Bob")],
    )
    promise.resolve(Error("Rolling back"))
  })
}
