import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}
import spaceship_db/driver.{
  type AsyncDriver, type Connection, type Statement, type Transaction,
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
pub fn driver(binding: String) -> AsyncDriver {
  driver.AsyncDriver(
    name: "d1",
    connect: fn(_name) { connect(binding) },
    close: close,
    prepare: prepare,
    exec: exec,
    begin: begin,
    commit: commit,
    rollback: rollback,
    begin_transaction_exec: fn(state, sql, params) {
      do_exec_tx(state, sql, params)
    },
    begin_transaction_commit: fn(state) { do_commit_tx(state) },
    begin_transaction_rollback: fn(state) { do_rollback_tx(state) },
  )
}

fn connect(binding: String) -> Promise(Result(Connection, String)) {
  // FFI to Cloudflare D1 binding
  do_connect(binding)
}

fn close(connection: Connection) -> Promise(Result(Nil, String)) {
  do_close(connection)
}

fn prepare(
  connection: Connection,
  sql: String,
) -> Promise(Result(Statement, String)) {
  do_prepare(connection, sql)
}

fn exec(
  statement: Statement,
  params: List(Value),
) -> Promise(Result(List(Dynamic), String)) {
  do_exec(statement, params)
}

fn begin(connection: Connection) -> Promise(Result(Transaction, String)) {
  promise.try_await(exec_sql(connection, "BEGIN"), fn(_) {
    promise.resolve(Ok(unsafe_wrap_transaction(connection)))
  })
}

fn commit(transaction: Transaction) -> Promise(Result(Nil, String)) {
  do_exec_sql_tx(transaction, "COMMIT")
}

fn rollback(transaction: Transaction) -> Promise(Result(Nil, String)) {
  do_exec_sql_tx(transaction, "ROLLBACK")
}

fn exec_sql(
  connection: Connection,
  sql: String,
) -> Promise(Result(Nil, String)) {
  promise.try_await(do_exec_sql(connection, sql), fn(_) {
    promise.resolve(Ok(Nil))
  })
}

// FFI bindings

@external(javascript, "../ffi/d1.mjs", "connect")
fn do_connect(binding: String) -> Promise(Result(Connection, String))

@external(javascript, "../ffi/d1.mjs", "close")
fn do_close(connection: Connection) -> Promise(Result(Nil, String))

@external(javascript, "../ffi/d1.mjs", "prepare")
fn do_prepare(
  connection: Connection,
  sql: String,
) -> Promise(Result(Statement, String))

@external(javascript, "../ffi/d1.mjs", "exec")
fn do_exec(
  statement: Statement,
  params: List(Value),
) -> Promise(Result(List(Dynamic), String))

@external(javascript, "../ffi/d1.mjs", "exec_sql")
fn do_exec_sql(
  connection: Connection,
  sql: String,
) -> Promise(Result(Nil, String))

// Transaction wrappers (opaque type conversion)

@external(javascript, "../ffi/d1.mjs", "wrap_transaction")
fn unsafe_wrap_transaction(connection: Connection) -> Transaction

@external(javascript, "../ffi/d1.mjs", "exec_sql_tx")
fn do_exec_sql_tx(
  transaction: Transaction,
  sql: String,
) -> Promise(Result(Nil, String))

// Async transaction FFI

@external(javascript, "../ffi/d1.mjs", "exec_tx")
fn do_exec_tx(
  state: Dynamic,
  sql: String,
  params: List(Value),
) -> Promise(Result(#(List(Dynamic), Dynamic), String))

@external(javascript, "../ffi/d1.mjs", "commit_tx")
fn do_commit_tx(state: Dynamic) -> Promise(Result(Nil, String))

@external(javascript, "../ffi/d1.mjs", "rollback_tx")
fn do_rollback_tx(state: Dynamic) -> Promise(Result(Nil, String))
