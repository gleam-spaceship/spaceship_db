// Cloudflare D1 driver FFI
// D1 is a serverless SQL database that works with Cloudflare Workers

// D1 connection wrapper
class D1Connection {
  constructor(binding) {
    this.binding = binding;
    this.prepared = new Map();
  }
}

// D1 statement wrapper
class D1Statement {
  constructor(sql, connection) {
    this.sql = sql;
    this.connection = connection;
  }
}

// D1 transaction wrapper
class D1Transaction {
  constructor(connection) {
    this.connection = connection;
  }
}

// Convert D1 row to Gleam-compatible format
function convertRow(row) {
  if (!row) return null;
  // D1 returns plain objects, we need to convert to a format Gleam can decode
  return row;
}

// Convert params to D1 format
function convertParams(params) {
  return params.map(param => {
    if (param && param.tag === 'Int') {
      return param[0];
    } else if (param && param.tag === 'Float') {
      return param[0];
    } else if (param && param.tag === 'Text') {
      return param[0];
    } else if (param && param.tag === 'Bool') {
      return param[0] ? 1 : 0;
    } else if (param && param.tag === 'Null') {
      return null;
    } else if (param && param.tag === 'BitArray') {
      return param[0];
    } else {
      // Try to extract value from object
      if (typeof param === 'object' && param !== null) {
        // Look for common patterns in Gleam dynamic values
        if ('0' in param) return param['0'];
        if ('value' in param) return param.value;
      }
      return param;
    }
  });
}

export function connect(bindingName) {
  try {
    // In Cloudflare Workers, the D1 binding is available on the env object
    // We need to get it from the global context or pass it through
    const binding = globalThis.__env?.[bindingName];
    if (!binding) {
      return { tag: 'Error', 0: `D1 binding '${bindingName}' not found` };
    }
    const conn = new D1Connection(binding);
    return { tag: 'Ok', 0: conn };
  } catch (error) {
    return { tag: 'Error', 0: error.toString() };
  }
}

export function close(connection) {
  // D1 connections don't need explicit closing
  return { tag: 'Ok', 0: undefined };
}

export function prepare(connection, sql) {
  try {
    const stmt = new D1Statement(sql, connection);
    return { tag: 'Ok', 0: stmt };
  } catch (error) {
    return { tag: 'Error', 0: error.toString() };
  }
}

export function exec(statement, params) {
  try {
    const d1Params = convertParams(params);
    
    // Use D1's batch API for better performance
    const result = statement.connection.binding
      .prepare(statement.sql)
      .bind(...d1Params)
      .all();
    
    return { tag: 'Ok', 0: result.results.map(convertRow) };
  } catch (error) {
    return { tag: 'Error', 0: error.toString() };
  }
}

export function exec_sql(connection, sql) {
  try {
    // Execute raw SQL without parameters
    const result = connection.binding
      .prepare(sql)
      .run();
    
    return { tag: 'Ok', 0: undefined };
  } catch (error) {
    return { tag: 'Error', 0: error.toString() };
  }
}

export function wrap_transaction(connection) {
  return new D1Transaction(connection);
}

export function unwrap_transaction(transaction) {
  return transaction.connection;
}
