import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import spaceship_db/driver.{
  type Connection, type Driver, type Statement, type Transaction,
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

/// Create a new database connection.
/// Use with:
/// ```gleam
/// use db <- spaceship_db.new(sqlite(path: "./app.db"))
/// ```
pub fn new(
  driver: Driver,
  f: fn(Db) -> Result(a, String),
) -> Result(a, String) {
  use conn <- result.try(driver.connect(driver.name))
  f(Db(driver:, connection: conn))
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
      "Decode error: expected "
      <> expected
      <> ", got "
      <> actual
      <> " at "
      <> path_str
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
