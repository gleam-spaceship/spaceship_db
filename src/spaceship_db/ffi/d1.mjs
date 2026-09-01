// Cloudflare D1 driver FFI.
// D1 operations are asynchronous and return JavaScript Promises.

import { Ok, Error, toList, BitArray } from "../../gleam.mjs";

class D1Connection {
  constructor(binding) {
    this.binding = binding;
  }
}

class D1Statement {
  constructor(sql, connection) {
    this.sql = sql;
    this.connection = connection;
  }
}

class D1Transaction {
  constructor(connection) {
    this.connection = connection;
  }
}

function errorMessage(error) {
  return error?.message || String(error);
}

function convertRow(row) {
  const values = Object.values(row).map((value) => {
    if (value === null) return undefined;
    if (value instanceof Uint8Array) return new BitArray(value);
    return value;
  });
  return toList(values);
}

function convertParams(params) {
  const values = [];
  let current = params;
  while (current && current.head !== undefined) {
    const param = current.head;
    if (param === null || param === undefined) values.push(null);
    else if (Object.prototype.hasOwnProperty.call(param, 0)) values.push(param[0]);
    else if (param.constructor?.name === "Null") values.push(null);
    else values.push(param);
    current = current.tail;
  }
  return values;
}

export function connect(bindingName) {
  return Promise.resolve().then(() => {
    const env = globalThis.__env;
    if (!env) throw new Error("No Cloudflare env available");

    const binding = env[bindingName];
    if (!binding) {
      throw new Error(`D1 binding '${bindingName}' not found in env`);
    }

    return new Ok(new D1Connection(binding));
  }).catch((error) => new Error(errorMessage(error)));
}

export function close(_connection) {
  return Promise.resolve(new Ok(undefined));
}

export function prepare(connection, sql) {
  return Promise.resolve().then(() => {
    return new Ok(new D1Statement(sql, connection));
  }).catch((error) => new Error(errorMessage(error)));
}

export function exec(statement, params) {
  return Promise.resolve()
    .then(() => statement.connection.binding
      .prepare(statement.sql)
      .bind(...convertParams(params))
      .all()
    )
    .then((result) => new Ok(toList(result.results.map(convertRow))))
    .catch((error) => new Error(errorMessage(error)));
}

export function exec_sql(connection, sql) {
  return Promise.resolve()
    .then(() => connection.binding.prepare(sql).run())
    .then(() => new Ok(undefined))
    .catch((error) => new Error(errorMessage(error)));
}

export function wrap_transaction(connection) {
  return new D1Transaction(connection);
}

export function unwrap_transaction(transaction) {
  return transaction.connection;
}
