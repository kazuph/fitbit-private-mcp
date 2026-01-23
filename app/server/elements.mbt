///| Custom HTML element helpers

///| Elements not provided by Luna UI's static_dom/element package

// =============================================================================
// Helper function
// =============================================================================

///|
/// Create a static attribute
fn static_attr(value : String) -> @luna.Attr[Unit] {
  @luna.attr_static(value)
}

///|
/// Build attribute array from common properties
fn build_attrs(
  id : String?,
  class : String?,
  style : String?,
  attrs : Array[(String, @luna.Attr[Unit])]?,
) -> Array[(String, @luna.Attr[Unit])] {
  let result : Array[(String, @luna.Attr[Unit])] = []
  if id is Some(v) {
    result.push(("id", static_attr(v)))
  }
  if class is Some(v) {
    result.push(("class", static_attr(v)))
  }
  if style is Some(v) {
    result.push(("style", static_attr(v)))
  }
  if attrs is Some(extra) {
    for attr in extra {
      result.push(attr)
    }
  }
  result
}

// =============================================================================
// Time Element (not in Luna UI)
// =============================================================================

///|
/// Create a time element
pub fn time(
  datetime? : String,
  id? : String,
  class? : String,
  style? : String,
  attrs? : Array[(String, @luna.Attr[Unit])],
  children : Array[@luna.Node[Unit]],
) -> @luna.Node[Unit] {
  let props = build_attrs(id, class, style, attrs)
  if datetime is Some(v) {
    props.push(("datetime", static_attr(v)))
  }
  @luna.h("time", props, children)
}

// =============================================================================
// Progress Element (custom component)
// =============================================================================

///|
/// Create a progress bar component
pub fn progress_bar(
  value : Int,
  max : Int,
  class? : String,
) -> @luna.Node[Unit] {
  let width_percent = if max > 0 { value * 100 / max } else { 0 }
  let bar_style = "width: " + width_percent.to_string() + "%"
  div(class=class.unwrap_or("progress-ring"), [
    div(class="progress-ring-fill", style=bar_style, []),
  ])
}
