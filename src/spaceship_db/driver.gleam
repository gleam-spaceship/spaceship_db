import gleam/dynamic.{type Dynamic}
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
