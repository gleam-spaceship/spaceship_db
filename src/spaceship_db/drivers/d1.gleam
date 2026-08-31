import gleam/dynamic.{type Dynamic}
import gleam/result
import spaceship_db/driver.{
  type Connection, type Driver, type Statement, type Transaction,
}
import spaceship_db/value.{type Value}

/// D1 driver configuration.
pub type Config {
  Config(binding: String)
}

/// Create a D1 driver config.
pub fn config(binding: String) -> Config {
  Config(binding:)
}

/// Create a D1 driver.
pub fn driver(binding: String) -> Driver {
  driver.Driver(
    name: "d1",
    connect: fn(_name) { connect(binding) },
    close: close,
    prepare: prepare,
    exec: exec,
    begin: begin,
    commit: commit,
    rollback: rollback,
  )
}

fn connect(binding: String) -> Result(Connection, String) {
  // FFI to Cloudflare D1 binding
  do_connect(binding)
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

@external(javascript, "../ffi/d1.mjs", "connect")
fn do_connect(binding: String) -> Result(Connection, String)

@external(javascript, "../ffi/d1.mjs", "close")
fn do_close(connection: Connection) -> Result(Nil, String)

@external(javascript, "../ffi/d1.mjs", "prepare")
fn do_prepare(connection: Connection, sql: String) -> Result(Statement, String)

@external(javascript, "../ffi/d1.mjs", "exec")
fn do_exec(
  statement: Statement,
  params: List(Value),
) -> Result(List(Dynamic), String)

@external(javascript, "../ffi/d1.mjs", "exec_sql")
fn do_exec_sql(connection: Connection, sql: String) -> Result(Nil, String)

// Transaction wrappers (opaque type conversion)

@external(javascript, "../ffi/d1.mjs", "wrap_transaction")
fn unsafe_wrap_transaction(connection: Connection) -> Transaction

@external(javascript, "../ffi/d1.mjs", "unwrap_transaction")
fn unsafe_unwrap_transaction(transaction: Transaction) -> Connection
