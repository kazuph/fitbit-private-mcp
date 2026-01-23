///|
/// Server-side element DSL imports
using @element {
  a,
  article,
  button,
  div,
  form,
  h1,
  h2,
  h3,
  nav,
  p,
  section,
  span,
  text,
}

///|
/// Wrapper for header element (MoonBit reserved word)
pub fn header(
  id? : String,
  class? : String,
  style? : String,
  attrs? : Array[(String, @luna.Attr[Unit])],
  children : Array[@luna.Node[Unit]],
) -> @luna.Node[Unit] {
  @element.header_(id?, class?, style?, attrs?, children)
}

///|
/// Wrapper for main element (MoonBit reserved word)
pub fn main_el(
  id? : String,
  class? : String,
  style? : String,
  attrs? : Array[(String, @luna.Attr[Unit])],
  children : Array[@luna.Node[Unit]],
) -> @luna.Node[Unit] {
  @element.main_(id?, class?, style?, attrs?, children)
}
