///|
/// Server-side element DSL imports
using @server_dom {
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
  attrs? : Array[(String, @luna.Attr[Unit, String])],
  children : Array[@luna.Node[Unit, String]],
) -> @luna.Node[Unit, String] {
  @server_dom.header_(id?, class?, style?, attrs?, children)
}

///|
/// Wrapper for main element (MoonBit reserved word)
pub fn main_el(
  id? : String,
  class? : String,
  style? : String,
  attrs? : Array[(String, @luna.Attr[Unit, String])],
  children : Array[@luna.Node[Unit, String]],
) -> @luna.Node[Unit, String] {
  @server_dom.main_(id?, class?, style?, attrs?, children)
}
