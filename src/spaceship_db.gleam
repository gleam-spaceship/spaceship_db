import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import spaceship_db/driver.{
  type AsyncDriver, type Connection, type Driver, type Statement,
  type Transaction,
}
import spaceship_db/value.{type Value}

/// Database handle.
pub type Db {
  Db(driver: Driver, connection: Connection)
}

/// Prepared statement bound to its database.
pub type Prepared {
  Prepared(db: Db, statement: Statement)
}

/// Database handle for asynchronous drivers.
pub type AsyncDb {
  AsyncDb(driver: AsyncDriver, connection: Connection)
}

/// Prepared statement for an asynchronous driver.
pub type AsyncPrepared {
  AsyncPrepared(db: AsyncDb, statement: Statement)
}

/// Use an asynchronous database connection and close it after the callback
/// completes.
pub fn with_async_db(
  driver: AsyncDriver,
  f: fn(AsyncDb) -> Promise(Result(a, String)),
) -> Promise(Result(a, String)) {
  promise.try_await(driver.connect(driver.name), fn(connection) {
    let db = AsyncDb(driver:, connection:)
    f(db)
    |> promise.await(fn(result) {
      driver.close(connection)
      |> promise.map(fn(_) { result })
    })
  })
}

/// Prepare a statement for an asynchronous driver.
pub fn prepare_async(
  db: AsyncDb,
  sql: String,
  f: fn(AsyncPrepared) -> Promise(Result(a, String)),
) -> Promise(Result(a, String)) {
  promise.try_await(db.driver.prepare(db.connection, sql), fn(statement) {
    f(AsyncPrepared(db:, statement:))
  })
}

/// Execute a statement for an asynchronous driver.
pub fn exec_async(
  prepared: AsyncPrepared,
  params: List(Value),
  f: fn(List(Dynamic)) -> Promise(Result(a, String)),
) -> Promise(Result(a, String)) {
  promise.try_await(
    prepared.db.driver.exec(prepared.statement, params),
    fn(rows) { f(rows) },
  )
}

/// Use a database connection with automatic cleanup.
/// The connection is closed when the callback returns.
/// Use with:
/// ```gleam
/// fn list_users() {
///   use db <- with_db(sqlite(path: "./app.db"))
///   use prepared <- prepare(db, "SELECT * FROM users")
///   exec(prepared, [])
/// }
/// ```
pub fn with_db(
  driver: Driver,
  f: fn(Db) -> Result(a, String),
) -> Result(a, String) {
  use conn <- result.try(driver.connect(driver.name))
  let db = Db(driver:, connection: conn)
  let result = f(db)
  let _ = close(db)
  result
}

/// Close the database connection.
pub fn close(db: Db) -> Result(Nil, String) {
  db.driver.close(db.connection)
}

/// Prepare a SQL statement.
/// Use with:
/// ```gleam
/// use prepared <- spaceship_db.prepare(db, "SELECT * FROM users")
/// ```
pub fn prepare(
  db: Db,
  sql: String,
  f: fn(Prepared) -> Result(a, String),
) -> Result(a, String) {
  use stmt <- result.try(db.driver.prepare(db.connection, sql))
  f(Prepared(db:, statement: stmt))
}

/// Execute a prepared statement with parameters.
/// Use with:
/// ```gleam
/// use rows <- spaceship_db.exec(prepared, [])
/// ```
/// Returns List(Dynamic) where each element is one row.
pub fn exec(
  prepared: Prepared,
  params: List(Value),
  f: fn(List(Dynamic)) -> Result(a, String),
) -> Result(a, String) {
  use rows <- result.try(prepared.db.driver.exec(prepared.statement, params))
  f(rows)
}

/// Get all rows from query results.
pub fn get_all(rows: List(Dynamic)) -> List(Dynamic) {
  rows
}

/// Get first row from query results. None if empty.
pub fn get_one(rows: List(Dynamic)) -> Option(Dynamic) {
  case rows {
    [first, ..] -> Some(first)
    [] -> None
  }
}

/// Decode all rows using a Decoder.
///
/// ```gleam
/// let user_decoder = {
///   use id <- decode.field(0, decode.int)
///   use name <- decode.field(1, decode.string)
///   decode.success(#(id, name))
/// }
/// let assert Ok(users) = spaceship_db.decode_all(rows, user_decoder)
/// ```
pub fn decode_all(
  rows: List(Dynamic),
  decoder: Decoder(t),
) -> Result(List(t), String) {
  list.try_map(rows, fn(row) {
    case decode.run(row, decoder) {
      Ok(value) -> Ok(value)
      Error(err) -> Error(decode_errors_to_string(err))
    }
  })
}

/// Decode first row using a Decoder.
pub fn decode_one(
  rows: List(Dynamic),
  decoder: Decoder(t),
) -> Result(t, String) {
  case rows {
    [row, ..] -> {
      case decode.run(row, decoder) {
        Ok(value) -> Ok(value)
        Error(err) -> Error(decode_errors_to_string(err))
      }
    }
    [] -> Error("No rows returned")
  }
}

fn decode_errors_to_string(errors: List(decode.DecodeError)) -> String {
  case errors {
    [] -> "Unknown decode error"
    [err, ..] -> {
      let decode.DecodeError(expected, actual, path) = err
      let path_str = case path {
        [] -> "root"
        _ ->
          list.fold(path, "", fn(acc, part) {
            case acc {
              "" -> part
              _ -> acc <> "." <> part
            }
          })
      }
      [
        "Decode error: expected ",
        expected,
        ", got ",
        actual,
        " at ",
        path_str,
      ]
      |> string.join("")
    }
  }
}

/// Execute a function within a transaction.
pub fn transaction(
  db: Db,
  f: fn(Transaction) -> Result(a, String),
) -> Result(a, String) {
  use tx <- result.try(db.driver.begin(db.connection))
  let result = f(tx)
  let _ = case result {
    Ok(_) -> db.driver.commit(tx)
    Error(_) -> db.driver.rollback(tx)
  }
  result
}
