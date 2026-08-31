/// Bindable parameter values for queries.
pub type Value {
  Int(Int)
  Float(Float)
  Text(String)
  Bool(Bool)
  Blob(BitArray)
  Null
}

pub fn int(value: Int) -> Value {
  Int(value)
}

pub fn float(value: Float) -> Value {
  Float(value)
}

pub fn text(value: String) -> Value {
  Text(value)
}

pub fn bool(value: Bool) -> Value {
  Bool(value)
}

pub fn blob(value: BitArray) -> Value {
  Blob(value)
}

pub fn null() -> Value {
  Null
}
