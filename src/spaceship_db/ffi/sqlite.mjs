import { DatabaseSync } from "node:sqlite";
import { Ok, Error, toList, BitArray, List } from "../../gleam.mjs";

export function connect(path) {
  try {
    const db = new DatabaseSync(path);
    return new Ok(db);
  } catch (error) {
    return new Error(error.message || String(error));
  }
}

export function close(connection) {
  try {
    connection.close();
    return new Ok(undefined);
  } catch (error) {
    if (error.message?.includes("database is not open")) {
      return new Ok(undefined);
    }
    return new Error(error.message || String(error));
  }
}

export function prepare(connection, sql) {
  try {
    const stmt = connection.prepare(sql);
    return new Ok(stmt);
  } catch (error) {
    return new Error(error.message || String(error));
  }
}

export function exec(statement, params) {
  try {
    const paramsArray = gleam_list_to_array(params);
    
    // Try all() first for SELECT queries
    try {
      const rows = statement.all(...paramsArray);
      const result = rows.map((row) => {
        const values = Object.values(row).map((val) => {
          if (val === null) return undefined;
          if (val instanceof Uint8Array) return new BitArray(val);
          return val;
        });
        return toList(values);
      });
      return new Ok(toList(result));
    } catch (e) {
      // If all() fails (non-SELECT), use run() and return empty list
      statement.run(...paramsArray);
      return new Ok(toList([]));
    }
  } catch (error) {
    return new Error(error.message || String(error));
  }
}

export function exec_sql(connection, sql) {
  try {
    connection.exec(sql);
    return new Ok(undefined);
  } catch (error) {
    return new Error(error.message || String(error));
  }
}

export function wrap_transaction(connection) {
  // Transaction is just the connection with BEGIN already called
  // We use an opaque wrapper to distinguish types at the Gleam level
  return { __gleam_transaction: true, connection };
}

export function unwrap_transaction(transaction) {
  return transaction.connection;
}

// Helper: Convert Gleam List to JS Array
function gleam_list_to_array(list) {
  const result = [];
  let current = list;
  while (current && current.head !== undefined) {
    result.push(value_to_js(current.head));
    current = current.tail;
  }
  return result;
}

// Helper: Convert Gleam Value to JS native type
function value_to_js(value) {
  if (value === undefined || value === null) return null;

  // Gleam custom type constructor names can be renamed by esbuild when
  // multiple modules define constructors with the same name. Scalar Value
  // constructors all store their value in field 0, so inspect the shape
  // before relying on constructor.name.
  if (Object.prototype.hasOwnProperty.call(value, 0)) return value[0];

  // Check for Gleam custom type constructors
  if (value.constructor?.name === "Int") return value[0];
  if (value.constructor?.name === "Float") return value[0];
  if (value.constructor?.name === "Text") return value[0];
  if (value.constructor?.name === "Bool") return value[0];
  if (value.constructor?.name === "Null") return null;
  if (value.constructor?.name === "Blob") {
    const bitArray = value[0];
    if (bitArray instanceof BitArray) {
      return new Uint8Array(bitArray.buffer, bitArray.byteOffset, bitArray.byteLength);
    }
    return bitArray;
  }

  // If it's already a native type, return as-is
  return value;
}
