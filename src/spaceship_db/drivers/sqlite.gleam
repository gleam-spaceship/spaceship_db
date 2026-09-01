import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}
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

/// Create an async SQLite driver.
pub fn async_driver(path: String) -> driver.AsyncDriver {
  driver.AsyncDriver(
    name: "sqlite",
    connect: fn(_name) { promise.resolve(connect(path)) },
    close: fn(conn) { promise.resolve(close(conn)) },
    prepare: fn(conn, sql) { promise.resolve(prepare(conn, sql)) },
    exec: fn(stmt, params) { promise.resolve(exec(stmt, params)) },
    begin: fn(conn) { promise.resolve(begin(conn)) },
    commit: fn(tx) { promise.resolve(commit(tx)) },
    rollback: fn(tx) { promise.resolve(rollback(tx)) },
    begin_transaction_exec: fn(state, sql, params) {
      do_exec_tx(state, sql, params)
    },
    begin_transaction_commit: fn(state) { do_commit_tx(state) },
    begin_transaction_rollback: fn(state) { do_rollback_tx(state) },
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
  do_exec_sql_tx(transaction, "COMMIT")
}

fn rollback(transaction: Transaction) -> Result(Nil, String) {
  do_exec_sql_tx(transaction, "ROLLBACK")
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

@external(javascript, "../ffi/sqlite.mjs", "exec_sql_tx")
fn do_exec_sql_tx(transaction: Transaction, sql: String) -> Result(Nil, String)

// Async transaction FFI

@external(javascript, "../ffi/sqlite.mjs", "exec_tx")
fn do_exec_tx(
  state: Dynamic,
  sql: String,
  params: List(Value),
) -> Promise(Result(#(List(Dynamic), Dynamic), String))

@external(javascript, "../ffi/sqlite.mjs", "commit_tx")
fn do_commit_tx(state: Dynamic) -> Promise(Result(Nil, String))

@external(javascript, "../ffi/sqlite.mjs", "rollback_tx")
fn do_rollback_tx(state: Dynamic) -> Promise(Result(Nil, String))
