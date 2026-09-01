import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/fetch
import gleam/http.{Post}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/string
import spaceship_db/driver.{
  type AsyncDriver, type Connection, type Statement, type Transaction,
  Connection, Statement,
}
import spaceship_db/value.{type Value, Blob, Bool, Float, Int, Null, Text}

/// Turso SQL-over-HTTP configuration.
pub type Config {
  Config(url: String, api_token: String)
}

/// Create a Turso driver configuration.
///
/// The URL may use `https://`, `turso://`, or `libsql://`. The latter two are
/// converted to `https://` for the SQL-over-HTTP endpoint.
pub fn config(url: String, api_token: String) -> Config {
  Config(url:, api_token:)
}

/// Create a Turso driver.
///
/// `url` is the database URL and `api_token` is a Turso database token.
pub fn driver(url: String, api_token: String) -> AsyncDriver {
  let url = normalise_url(url)
  driver.AsyncDriver(
    name: "turso",
    connect: fn(_name) { connect(url, api_token) },
    close: close,
    prepare: prepare,
    exec: exec,
    begin: begin,
    commit: commit,
    rollback: rollback,
  )
}

fn connect(
  url: String,
  api_token: String,
) -> Promise(Result(Connection, String)) {
  promise.resolve(Ok(Connection(url:, api_token:)))
}

fn close(_connection: Connection) -> Promise(Result(Nil, String)) {
  promise.resolve(Ok(Nil))
}

fn prepare(
  connection: Connection,
  sql: String,
) -> Promise(Result(Statement, String)) {
  promise.resolve(Ok(Statement(connection:, sql:)))
}

fn exec(
  statement: Statement,
  params: List(Value),
) -> Promise(Result(List(dynamic.Dynamic), String)) {
  let Statement(connection:, sql:) = statement
  execute(connection, sql, params)
}

fn begin(_connection: Connection) -> Promise(Result(Transaction, String)) {
  promise.resolve(Error(
    "Turso HTTP transactions are not supported by this driver yet",
  ))
}

fn commit(_transaction: Transaction) -> Promise(Result(Nil, String)) {
  promise.resolve(Error(
    "Turso HTTP transactions are not supported by this driver yet",
  ))
}

fn rollback(_transaction: Transaction) -> Promise(Result(Nil, String)) {
  promise.resolve(Error(
    "Turso HTTP transactions are not supported by this driver yet",
  ))
}

fn execute(
  connection: Connection,
  sql: String,
  params: List(Value),
) -> Promise(Result(List(dynamic.Dynamic), String)) {
  let body = pipeline_body(sql, params) |> json.to_string
  let Connection(url:, api_token:) = connection

  case request.to(url <> "/v2/pipeline") {
    Error(_) -> promise.resolve(Error("Invalid Turso database URL"))
    Ok(req) -> {
      req
      |> request.set_method(Post)
      |> request.set_header("authorization", "Bearer " <> api_token)
      |> request.set_header("content-type", "application/json")
      |> request.set_body(body)
      |> fetch.send
      |> promise.await(fn(result) {
        case result {
          Error(error) -> promise.resolve(Error(fetch_error(error)))
          Ok(response) -> decode_fetch_response(response)
        }
      })
    }
  }
}

fn decode_fetch_response(
  response: Response(fetch.FetchBody),
) -> Promise(Result(List(dynamic.Dynamic), String)) {
  fetch.read_json_body(response)
  |> promise.await(fn(result) {
    case result {
      Error(error) -> promise.resolve(Error(fetch_error(error)))
      Ok(response) -> {
        case response.status >= 200 && response.status < 300 {
          True -> promise.resolve(decode_pipeline(response.body))
          False ->
            promise.resolve(Error(
              "Turso returned HTTP status " <> int.to_string(response.status),
            ))
        }
      }
    }
  })
}

fn decode_pipeline(
  body: dynamic.Dynamic,
) -> Result(List(dynamic.Dynamic), String) {
  let result_type =
    decode.run(
      body,
      decode.at(["results"], decode.at([0], decode.at(["type"], decode.string))),
    )

  case result_type {
    Ok("ok") -> {
      let rows = decode.run(body, rows_decoder())
      case rows {
        Ok(rows) -> Ok(rows)
        Error(_) -> Error("Invalid Turso result rows")
      }
    }
    Ok("error") -> {
      case
        decode.run(
          body,
          decode.at(
            ["results"],
            decode.at([0], decode.at(["error", "message"], decode.string)),
          ),
        )
      {
        Ok(message) -> Error("Turso query failed: " <> message)
        Error(_) -> Error("Turso query failed")
      }
    }
    Ok(_) -> Error("Invalid Turso result type")
    Error(_) -> Error("Invalid Turso pipeline response")
  }
}

fn rows_decoder() -> decode.Decoder(List(dynamic.Dynamic)) {
  decode.at(
    ["results"],
    decode.at(
      [0],
      decode.at(
        ["response"],
        decode.at(
          ["result"],
          decode.at(
            ["rows"],
            decode.list(decode.list(value_decoder()))
              |> decode.map(fn(rows) { list.map(rows, dynamic.list) }),
          ),
        ),
      ),
    ),
  )
}

fn value_decoder() -> decode.Decoder(dynamic.Dynamic) {
  decode.field("type", decode.string, fn(kind) {
    case kind {
      "null" -> decode.success(dynamic.nil())
      "integer" -> decode_integer()
      "float" -> decode_float()
      "text" -> decode_text()
      "blob" -> decode_blob()
      _ -> decode.failure(dynamic.nil(), expected: "Turso value")
    }
  })
}

fn decode_integer() -> decode.Decoder(dynamic.Dynamic) {
  decode.field("value", decode.string, fn(value) {
    case int.parse(value) {
      Ok(value) -> decode.success(dynamic.int(value))
      Error(_) -> decode.failure(dynamic.nil(), expected: "integer")
    }
  })
}

fn decode_float() -> decode.Decoder(dynamic.Dynamic) {
  decode.field("value", decode.float, fn(value) {
    decode.success(dynamic.float(value))
  })
}

fn decode_text() -> decode.Decoder(dynamic.Dynamic) {
  decode.field("value", decode.string, fn(value) {
    decode.success(dynamic.string(value))
  })
}

fn decode_blob() -> decode.Decoder(dynamic.Dynamic) {
  decode.field("base64", decode.string, fn(value) {
    case bit_array.base64_decode(value) {
      Ok(value) -> decode.success(dynamic.bit_array(value))
      Error(_) -> decode.failure(dynamic.nil(), expected: "base64 blob")
    }
  })
}

fn pipeline_body(sql: String, params: List(Value)) -> json.Json {
  let execute_request =
    json.object([
      #("type", json.string("execute")),
      #(
        "stmt",
        json.object([
          #("sql", json.string(sql)),
          #("args", json.array(params, encode_value)),
          #("want_rows", json.bool(True)),
        ]),
      ),
    ])
  let close_request = json.object([#("type", json.string("close"))])

  json.object([
    #("baton", json.null()),
    #(
      "requests",
      json.array([execute_request, close_request], fn(value) { value }),
    ),
  ])
}

fn encode_value(value: Value) -> json.Json {
  case value {
    Int(value) ->
      json.object([
        #("type", json.string("integer")),
        #("value", json.string(int.to_string(value))),
      ])
    Float(value) ->
      json.object([
        #("type", json.string("float")),
        #("value", json.float(value)),
      ])
    Text(value) ->
      json.object([
        #("type", json.string("text")),
        #("value", json.string(value)),
      ])
    Bool(value) ->
      json.object([
        #("type", json.string("integer")),
        #(
          "value",
          json.string(case value {
            True -> "1"
            False -> "0"
          }),
        ),
      ])
    Blob(value) ->
      json.object([
        #("type", json.string("blob")),
        #("base64", json.string(bit_array.base64_encode(value, False))),
      ])
    Null -> json.object([#("type", json.string("null"))])
  }
}

fn fetch_error(error: fetch.FetchError) -> String {
  case error {
    fetch.NetworkError(message) -> "Turso network error: " <> message
    fetch.UnableToReadBody -> "Unable to read Turso response body"
    fetch.InvalidJsonBody -> "Turso returned invalid JSON"
  }
}

fn normalise_url(url: String) -> String {
  let url =
    url
    |> string.replace("turso://", "https://")
    |> string.replace("libsql://", "https://")

  case string.ends_with(url, "/") {
    True -> string.drop_end(url, 1)
    False -> url
  }
}
