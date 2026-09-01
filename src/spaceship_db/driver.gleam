import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}
import spaceship_db/value.{type Value}

/// Opaque database connection handle.
pub type Connection

/// Prepared statement — reusable across executions.
pub type Statement

/// Transaction context.
pub type Transaction

/// Driver trait — every backend implements this.
pub type Driver {
  Driver(
    name: String,
    connect: fn(String) -> Result(Connection, String),
    close: fn(Connection) -> Result(Nil, String),
    prepare: fn(Connection, String) -> Result(Statement, String),
    exec: fn(Statement, List(Value)) -> Result(List(Dynamic), String),
    begin: fn(Connection) -> Result(Transaction, String),
    commit: fn(Transaction) -> Result(Nil, String),
    rollback: fn(Transaction) -> Result(Nil, String),
  )
}

/// A database driver whose operations may be asynchronous.
///
/// JavaScript database APIs such as Cloudflare D1 return Promises. Keep this
/// separate from Driver so synchronous drivers remain easy to use.
pub type AsyncDriver {
  AsyncDriver(
    name: String,
    connect: fn(String) -> Promise(Result(Connection, String)),
    close: fn(Connection) -> Promise(Result(Nil, String)),
    prepare: fn(Connection, String) -> Promise(Result(Statement, String)),
    exec: fn(Statement, List(Value)) -> Promise(Result(List(Dynamic), String)),
    begin: fn(Connection) -> Promise(Result(Transaction, String)),
    commit: fn(Transaction) -> Promise(Result(Nil, String)),
    rollback: fn(Transaction) -> Promise(Result(Nil, String)),
  )
}
