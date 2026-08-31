import gleam/dynamic.{type Dynamic}
import gleam/result
import spaceship_db/driver.{
  type Connection, type Driver, type Statement, type Transaction,
}
import spaceship_db/value.{type Value}

/// SQLite driver configuration.
pub type Config {
  Config(path: String)
}

/// Create a SQLite driver config.
pub fn config(path: String) -> Config {
  Config(path:)
}

/// Create a SQLite driver.
pub fn driver(path: String) -> Driver {
  driver.Driver(
    name: "sqlite",
    connect: fn(_name) { connect(path) },
    close: close,
    prepare: prepare,
    exec: exec,
    begin: begin,
    commit: commit,
    rollback: rollback,
  )
}

fn connect(path: String) -> Result(Connection, String) {
  // FFI to node:sqlite DatabaseSync
  do_connect(path)
}

fn close(connection: Connection) -> Result(Nil, String) {
  do_close(connection)
}

fn prepare(connection: Connection, sql: String) -> Result(Statement, String) {
  do_prepare(connection, sql)
}

fn exec(
  statement: Statement,
  params: List(Value),
) -> Result(List(Dynamic), String) {
  do_exec(statement, params)
}

fn begin(connection: Connection) -> Result(Transaction, String) {
  use _ <- result.try(exec_sql(connection, "BEGIN"))
  Ok(unsafe_wrap_transaction(connection))
}

fn commit(transaction: Transaction) -> Result(Nil, String) {
  let conn = unsafe_unwrap_transaction(transaction)
  exec_sql(conn, "COMMIT")
}

fn rollback(transaction: Transaction) -> Result(Nil, String) {
  let conn = unsafe_unwrap_transaction(transaction)
  exec_sql(conn, "ROLLBACK")
}

fn exec_sql(connection: Connection, sql: String) -> Result(Nil, String) {
  use _ <- result.try(do_exec_sql(connection, sql))
  Ok(Nil)
}

// FFI bindings

@external(javascript, "../ffi/sqlite.mjs", "connect")
fn do_connect(path: String) -> Result(Connection, String)

@external(javascript, "../ffi/sqlite.mjs", "close")
fn do_close(connection: Connection) -> Result(Nil, String)

@external(javascript, "../ffi/sqlite.mjs", "prepare")
fn do_prepare(connection: Connection, sql: String) -> Result(Statement, String)

@external(javascript, "../ffi/sqlite.mjs", "exec")
fn do_exec(
  statement: Statement,
  params: List(Value),
) -> Result(List(Dynamic), String)

@external(javascript, "../ffi/sqlite.mjs", "exec_sql")
fn do_exec_sql(connection: Connection, sql: String) -> Result(Nil, String)

// Transaction wrappers (opaque type conversion)

@external(javascript, "../ffi/sqlite.mjs", "wrap_transaction")
fn unsafe_wrap_transaction(connection: Connection) -> Transaction

@external(javascript, "../ffi/sqlite.mjs", "unwrap_transaction")
fn unsafe_unwrap_transaction(transaction: Transaction) -> Connection
