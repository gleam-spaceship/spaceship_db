// Turso transaction state conversion between Gleam types and plain JS objects.

import { Ok, Error } from "../../gleam.mjs";

export function state_to_dynamic(state) {
  return {
    url: state.url,
    api_token: state.api_token,
    baton: state.baton,
  };
}

export function dynamic_to_state(d) {
  return {
    url: d.url,
    api_token: d.api_token,
    baton: d.baton,
  };
}
